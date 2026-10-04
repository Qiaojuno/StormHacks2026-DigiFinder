// Fuzzy matching of OCR text against the goal (§5.2 pointing).

/// `text` and `term` in normalizeText form. Matches whole-word windows within `maxDistance` edits.
public func fuzzyContains(_ text: String, _ term: String, maxDistance: Int = 1) -> Bool {
    if text.contains(term) { return true }
    let words = text.split(separator: " ").map(String.init), n = term.split(separator: " ").count
    guard n > 0, words.count >= n else { return false }
    for i in 0...(words.count - n) where levenshtein(words[i..<i+n].joined(separator: " "), term) <= maxDistance { return true }
    return false
}

/// ≥ 0.9 match; 0.5–0.9 near-miss; 0 = wrong brand.
public func score(_ ocr: String, _ g: Goal) -> Double {
    let t = normalizeText(ocr)
    if let b = g.brand, !fuzzyContains(t, normalizeText(b)) { return 0 }
    var s = 0.5
    s += 0.3 * Double(g.variant.filter { fuzzyContains(t, normalizeText($0)) }.count) / Double(max(g.variant.count, 1))
    if let f = g.form, fuzzyContains(t, normalizeText(f)) || g.synonyms.contains(where: { fuzzyContains(t, normalizeText($0)) }) { s += 0.2 }
    return s
}
