// Fuzzy matching of OCR text against the goal (§5.2 pointing).

/// Score thresholds shared by perception and the flow.
public enum MatchingThresholds {
    /// `score` at or above: the pointed product is the goal.
    public static let pointMatch = 0.9
    /// `score` at or above (below `pointMatch`): near miss, e.g. right brand, wrong variant.
    public static let nearMiss = 0.5
    /// `confirmFromLabel` coverage at or above: the held item is identified.
    public static let confirm = 0.8
}

/// Whole-word fuzzy containment. `text` and `term` in normalizeText form.
/// A window of words matches when each word equals the term's word (plural "s"/"es" allowed),
/// or the window is within `maxDistance` edits (terms of 4+ letters only, so "tea" never matches "pea"),
/// or it matches with a space dropped or added by OCR ("darkroast" / "star bucks").
public func fuzzyContains(_ text: String, _ term: String, maxDistance: Int = 1) -> Bool {
    let words = text.split(separator: " ").map(String.init)
    let termWords = term.split(separator: " ").map(String.init)
    let n = termWords.count
    guard n > 0, !words.isEmpty else { return false }
    let joined = termWords.joined(separator: " ")
    let compact = termWords.joined()
    let allowed = compact.count >= 4 ? max(maxDistance, 0) : 0

    if words.count >= n {
        for i in 0...(words.count - n) {
            let window = words[i..<i + n]
            if zip(window, termWords).allSatisfy({ wordsMatchAllowingPlural($0, $1) }) { return true }
            if allowed > 0 && withinEditDistance(window.joined(separator: " "), joined, allowed) { return true }
        }
    }
    // Spaces dropped or added: compare without spaces over windows of n-1 ... n+1 words.
    for size in max(1, n - 1)...(n + 1) where size <= words.count && (size != n || n > 1) {
        for i in 0...(words.count - size) {
            let w = words[i..<i + size].joined()
            if w == compact || (allowed > 0 && withinEditDistance(w, compact, allowed)) { return true }
        }
    }
    return false
}

/// ≥ 0.9 match; 0.5–0.9 near-miss; 0 = wrong brand or nothing of the goal in the text.
/// The text must show the goal's brand (if the user said one), or its product name / a synonym.
/// Then 0.5 + 0.3 × share of the said variants + 0.2 for the said form (or a goal synonym).
/// Variants or a form the user didn't say count as matched, so "milk" on "Dairyland 2% milk" scores 1.0.
public func score(_ ocr: String, _ g: Goal) -> Double {
    score(ocr, g, candidates: [], synonyms: .none)
}

/// Same, plus: a goal candidate whose brand + name words mostly appear in the text (≥ 60 %) also anchors the
/// match ("Starbucks Pike Place" for the goal "coffee"), and catalog synonyms count for every goal word.
public func score(_ ocr: String, _ g: Goal, candidates: [ProductInfo], synonyms: MatchingSynonyms = .none) -> Double {
    let t = normalizeText(ocr)
    guard !t.isEmpty else { return 0 }
    func found(_ term: String) -> Bool {
        let alts = synonyms.alternatives(for: term)
        return alts.contains { fuzzyContains(t, $0) }
    }
    let brand = g.brand.map(normalizeText).flatMap { $0.isEmpty ? nil : $0 }
    if let b = brand, !found(b) { return 0 }
    let goalSynonyms = g.synonyms.map(normalizeText).filter { !$0.isEmpty }
    let product = normalizeText(g.product)
    let anchored = brand != nil
        || (!product.isEmpty && found(product))
        || goalSynonyms.contains(where: found)
        || candidates.contains { labelCoverage(t, $0).share >= 0.6 }
    guard anchored else { return 0 }

    var s = 0.5
    let variants = g.variant.map(normalizeText).filter { !$0.isEmpty }
    s += variants.isEmpty ? 0.3 : 0.3 * Double(variants.filter(found).count) / Double(variants.count)
    if let f = g.form.map(normalizeText), !f.isEmpty {
        if found(f) || goalSynonyms.contains(where: found) { s += 0.2 }
    } else {
        s += 0.2
    }
    return min(s, 1)
}

/// Words too common on labels to decide anything.
let matchingStopWords: Set<String> = ["s", "the", "a", "an", "and", "of", "with", "de", "du", "la", "le", "et", "for", "in", "to", "or", "by"]

/// Share of a product's brand + name words that appear in a normalized label (stop words ignored unless
/// that leaves nothing), and how many words matched.
func labelCoverage(_ normalizedLabel: String, _ p: ProductInfo) -> (share: Double, matched: Int) {
    var words = normalizedWords("\(p.brand ?? "") \(p.name)")
    var seen = Set<String>()
    words = words.filter { seen.insert($0).inserted }
    let content = words.filter { !matchingStopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    let use = content.isEmpty ? words : content
    guard !use.isEmpty else { return (0, 0) }
    let matched = use.filter { fuzzyContains(normalizedLabel, $0) }.count
    return (Double(matched) / Double(use.count), matched)
}
