// Signs and word search (§5.2 find signage, unknown items, §5.6 destinations).

/// Normalized words to look for on signs for this goal.
/// Known aisle: the aisle key + its `aisleWords` + the product and its synonyms.
/// Unknown item (category nil or not in the catalog): the spoken words + synonyms + `signWords` (word search).
public func signTerms(for goal: Goal, catalog: [String: AisleInfo], synonyms: MatchingSynonyms = .none) -> [String] {
    var out: [String] = []
    func add(_ s: String) { let n = normalizeText(s); if !n.isEmpty && !out.contains(n) { out.append(n) } }
    if let c = goal.category, let info = catalog[c] {
        add(c)
        info.aisleWords.forEach(add)
    }
    synonyms.alternatives(for: goal.product).forEach(add)
    goal.synonyms.forEach(add)
    if goal.category == nil || catalog[goal.category ?? ""] == nil { goal.signWords.forEach(add) }
    return out
}

/// Goal terms found on a sign, in `signTerms` order. Plurals allowed; one OCR typo allowed for words of 5+ letters.
public func signMatchedTerms(_ signWords: [String], goal: Goal, catalog: [String: AisleInfo],
                             synonyms: MatchingSynonyms = .none) -> [String] {
    let text = normalizeText(signWords.joined(separator: " "))
    guard !text.isEmpty else { return [] }
    return signTerms(for: goal, catalog: catalog, synonyms: synonyms).filter { term in
        containsPhrase(text, term, allowPlural: true) || (term.count >= 5 && fuzzyContains(text, term))
    }
}

/// True when the sign names the goal's aisle (or, for word search, one of its words).
public func signMatches(_ sign: AisleSign, goal: Goal, catalog: [String: AisleInfo], synonyms: MatchingSynonyms = .none) -> Bool {
    !signMatchedTerms(sign.words, goal: goal, catalog: catalog, synonyms: synonyms).isEmpty
}

/// The aisle a sign names: most matched `aisleWords` (+ the aisle key); ties go to the aisle whose own name
/// appears first on the sign ("Coffee, Tea" → coffee), then alphabetically.
public func aisleForSign(_ signWords: [String], catalog: [String: AisleInfo]) -> String? {
    let text = normalizeText(signWords.joined(separator: " "))
    guard !text.isEmpty else { return nil }
    let words = text.split(separator: " ").map(String.init)
    func firstIndex(of phrase: String) -> Int {
        let p = phrase.split(separator: " ").map(String.init)
        guard !p.isEmpty, words.count >= p.count else { return Int.max }
        for i in 0...(words.count - p.count) where zip(words[i..<i + p.count], p).allSatisfy({ wordsMatchAllowingPlural($0, $1) }) {
            return i
        }
        return Int.max
    }
    var best: (aisle: String, hits: Int, keyAt: Int)?
    for aisle in catalog.keys.sorted() {
        guard let info = catalog[aisle] else { continue }
        let terms = Set(([aisle] + info.aisleWords).map(normalizeText).filter { !$0.isEmpty })
        let hits = terms.filter { firstIndex(of: $0) != Int.max }.count
        guard hits > 0 else { continue }
        let keyAt = firstIndex(of: normalizeText(aisle))
        if let b = best, hits < b.hits || (hits == b.hits && keyAt >= b.keyAt) { continue }
        best = (aisle, hits, keyAt)
    }
    return best?.aisle
}

/// Destination named by a sign ("Customer Service", "Self Checkout", "Lane 4").
/// "help" / "information" count only on short signs (≤ 3 words), so "Nutrition information" isn't a desk.
public func destinationForSign(_ signWords: [String], destinations: [Destination: [String]]) -> Destination? {
    let text = normalizeText(signWords.joined(separator: " "))
    guard !text.isEmpty else { return nil }
    let wordCount = text.split(separator: " ").count
    var best: (d: Destination, len: Int)?
    for d in destinations.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        for raw in destinations[d] ?? [] {
            let w = normalizeText(raw)
            guard !w.isEmpty, containsPhrase(text, w, allowPlural: true) else { continue }
            if RequestRouter.aloneOnly.contains(w) && wordCount > 3 { continue }
            if let b = best, w.count <= b.len { continue }
            best = (d, w.count)
        }
    }
    return best?.d
}

/// Word search at the shelf (unknown items): the spoken words (or a goal synonym) appear on the label.
/// Confirmation then reads the label back ("This says Cedar's tahini.").
public func wordSearchLabelMatches(_ label: String, goal: Goal, synonyms: MatchingSynonyms = .none) -> Bool {
    let text = normalizeText(label)
    guard !text.isEmpty else { return false }
    let terms = (synonyms.alternatives(for: goal.product) + goal.synonyms.map(normalizeText)).filter { !$0.isEmpty }
    return terms.contains { containsPhrase(text, $0, allowPlural: true) || fuzzyContains(text, $0) }
}
