// Held-item label confirmation (§5.2 grab and check).

/// Best candidate and its word coverage (0...1).
/// ≥ 0.8 and goal → success; ≥ 0.8 other → "That's <name>, not <goal>."; < 0.8 → "Turn it slowly."
public func confirmFromLabel(_ label: String, candidates: [ProductInfo]) -> (ProductInfo, Double)? {
    let l = normalizeText(label)
    func coverage(_ p: ProductInfo) -> Double {
        let words = normalizeText("\(p.brand ?? "") \(p.name)").split(separator: " ").map(String.init)
        guard !words.isEmpty else { return 0 }
        var s = Double(words.filter { fuzzyContains(l, $0) }.count) / Double(words.count)
        if let q = p.quantity, fuzzyContains(l, normalizeText(q)) { s += 0.1 }
        return min(s, 1)
    }
    return candidates.map { ($0, coverage($0)) }.max { $0.1 < $1.1 }
}
