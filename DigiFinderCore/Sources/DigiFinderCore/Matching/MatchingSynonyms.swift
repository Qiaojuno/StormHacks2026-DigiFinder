// Synonym groups from synonyms.json `synonyms` ("peanut butter": ["pb", "peanut spread"]).
// Used by the router (retry a failed search with the canonical words) and by label matching
// (a goal word also matches any of its synonyms).

public struct MatchingSynonyms: Equatable {
    /// Each group is normalized and starts with the canonical phrase (the JSON key).
    public private(set) var groups: [[String]] = []

    public static let none = MatchingSynonyms()

    public init(_ table: [String: [String]] = [:]) {
        for key in table.keys.sorted() {
            var group: [String] = []
            for w in [key] + (table[key] ?? []) {
                let n = normalizeText(w)
                if !n.isEmpty && !group.contains(n) { group.append(n) }
            }
            if group.count > 1 { groups.append(group) }
        }
    }

    /// The canonical phrase for `term` (normalized), or nil if it isn't in any group.
    public func canonical(for term: String) -> String? {
        let t = normalizeText(term)
        return groups.first { $0.contains(t) }?.first
    }

    /// `term` first, then every phrase it can stand for: whole-term synonyms, then single substitutions
    /// of a synonym phrase inside the term ("crunchy pb" → "crunchy peanut butter"). All normalized, no duplicates.
    public func alternatives(for term: String, limit: Int = 12) -> [String] {
        let t = normalizeText(term)
        guard !t.isEmpty else { return [] }
        var out = [t]
        func add(_ s: String) { if out.count < limit && !s.isEmpty && !out.contains(s) { out.append(s) } }
        for g in groups where g.contains(t) { g.forEach(add) }
        for g in groups {
            for member in g where member != t && containsPhrase(t, member) {
                for other in g where other != member { add(replacePhrase(in: t, member, with: other)) }
            }
        }
        return out
    }

    /// Replaces every non-canonical synonym phrase in `text` with its canonical phrase (longest phrases first).
    public func canonicalize(_ text: String) -> String {
        var t = normalizeText(text)
        let pairs = groups.flatMap { g in g.dropFirst().map { (variant: $0, canonical: g[0]) } }
            .sorted { $0.variant.count > $1.variant.count }
        for p in pairs where containsPhrase(t, p.variant) { t = replacePhrase(in: t, p.variant, with: p.canonical) }
        return t
    }
}

/// Whole-word replacement in normalized text, left to right, non-overlapping.
func replacePhrase(in text: String, _ phrase: String, with replacement: String) -> String {
    let w = text.split(separator: " ").map(String.init)
    let p = phrase.split(separator: " ").map(String.init)
    let r = replacement.split(separator: " ").map(String.init)
    guard !p.isEmpty else { return text }
    var out: [String] = []
    var i = 0
    while i < w.count {
        if i + p.count <= w.count && Array(w[i..<i + p.count]) == p {
            out += r; i += p.count
        } else {
            out.append(w[i]); i += 1
        }
    }
    return out.joined(separator: " ")
}
