// Held-item label confirmation (§5.2 grab and check): label text first, a visible barcode wins.

/// Best candidate and its word coverage (0...1).
/// ≥ 0.8 and goal → success; ≥ 0.8 other → "That's <name>, not <goal>."; < 0.8 → "Turn it slowly."
/// Coverage = share of the candidate's brand + name words on the label, +0.1 when its size is on the label,
/// −0.2 when the label shows a different size of the same kind (680 g vs 340 g).
/// Ties go to the candidate with more matched words (the more specific name), then the larger raw score.
/// nil when there are no candidates or the label is empty.
public func confirmFromLabel(_ label: String, candidates: [ProductInfo]) -> (ProductInfo, Double)? {
    let l = normalizeText(label)
    guard !l.isEmpty else { return nil }
    let labelSizes = MatchingQuantity.all(in: label)
    var best: (p: ProductInfo, raw: Double, matched: Int)?
    for p in candidates {
        let cov = labelCoverage(l, p)
        var raw = cov.share
        if let q = productQuantity(p) {
            let sameKind = labelSizes.filter { $0.family == q.family }
            if sameKind.contains(where: { $0.isSameAmount(as: q) }) {
                raw += 0.1
            } else if !sameKind.isEmpty {
                raw -= 0.2
            }
        } else if let q = p.quantity, !normalizeText(q).isEmpty, fuzzyContains(l, normalizeText(q)) {
            raw += 0.1
        }
        if let b = best {
            let better = raw > b.raw + 1e-9 || (abs(raw - b.raw) <= 1e-9 && cov.matched > b.matched)
            if !better { continue }
        }
        best = (p, raw, cov.matched)
    }
    return best.map { ($0.p, min(max($0.raw, 0), 1)) }
}

/// The candidate with this barcode (12-digit UPCs padded like the database), or nil.
public func confirmFromBarcode(_ code: String, candidates: [ProductInfo]) -> ProductInfo? {
    let c = normalizeBarcode(code)
    guard !c.isEmpty else { return nil }
    return candidates.first { normalizeBarcode($0.code) == c }
}

/// A visible barcode that matches a candidate wins (score 1); otherwise the label decides.
public func confirmHeldItem(label: String, barcode: String?, candidates: [ProductInfo]) -> (ProductInfo, Double)? {
    if let b = barcode, let p = confirmFromBarcode(b, candidates: candidates) { return (p, 1) }
    return confirmFromLabel(label, candidates: candidates)
}

/// Wrong-item line: "That's ground, not whole bean." when the found product lacks a variant/form the user said
/// and has its own distinguishing words; otherwise "That's <found>, not <goal>."
public func wrongItemLine(found: ProductInfo, goal: Goal) -> String {
    let foundText = normalizeText("\(found.brand ?? "") \(found.name)")
    let said = (goal.variant + [goal.form].compactMap { $0 }).map(normalizeText).filter { !$0.isEmpty }
    let missing = said.filter { !fuzzyContains(foundText, $0) }
    let known = Set(([goal.brand, goal.product].compactMap { $0 } + goal.variant + [goal.form].compactMap { $0 } + goal.synonyms)
        .flatMap(normalizedWords))
    let brandWords = Set(normalizedWords(found.brand ?? ""))
    let extra = normalizedWords(found.name).filter {
        !known.contains($0) && !brandWords.contains($0) && !matchingStopWords.contains($0) && !$0.allSatisfy(\.isNumber)
    }
    if !missing.isEmpty && !extra.isEmpty {
        return "That's \(extra.joined(separator: " ")), not \(missing.joined(separator: " and "))."
    }
    let goalName = ([goal.brand].compactMap { $0 } + goal.variant + [goal.product] + [goal.form].compactMap { $0 })
        .joined(separator: " ")
    return "That's \(spokenProduct(found, quantity: false)), not \(goalName)."
}
