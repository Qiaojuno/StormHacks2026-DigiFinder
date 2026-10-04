// Shelf vote (§5.7): labels and YOLO objects vote for an aisle, each once.

public struct AisleVote {
    public private(set) var counts: [String: Int] = [:]
    /// Words / YOLO classes that voted, per aisle, in first-seen order (for "I see coffee and tea on both sides").
    public private(set) var evidence: [String: [String]] = [:]
    private var seen = Set<String>()
    public init() {}

    public var total: Int { counts.values.reduce(0, +) }

    /// One vote per distinct label text. The most specific (longest) whole-word match wins; plurals allowed.
    /// Map keys may be raw or normalized; use `AisleVote.wordToAisle(_:)` to build the map from categories.json.
    public mutating func addText(_ label: String, wordToAisle: [String: String]) {
        let key = normalizeText(label)
        guard !key.isEmpty, !seen.contains(key) else { return }
        var best: (word: String, aisle: String)?
        for (raw, aisle) in wordToAisle {
            let w = normalizeText(raw)
            guard !w.isEmpty, containsPhrase(key, w, allowPlural: true) else { continue }
            if let b = best, w.count < b.word.count || (w.count == b.word.count && (w, aisle) >= (b.word, b.aisle)) { continue }
            best = (w, aisle)
        }
        guard let b = best else { return }
        counts[b.aisle, default: 0] += 1
        seen.insert(key)
        note(b.word, for: b.aisle)
    }

    /// One vote per tracked object. Class lookup is exact first, then case-insensitive.
    public mutating func addVisual(trackID: Int, yoloClass: String, classToAisle: [String: String]) {
        let key = "yolo-\(trackID)"
        guard !seen.contains(key) else { return }
        let wanted = normalizeText(yoloClass)
        guard let a = classToAisle[yoloClass]
                ?? classToAisle.keys.sorted().first(where: { normalizeText($0) == wanted }).flatMap({ classToAisle[$0] })
        else { return }
        counts[a, default: 0] += 1
        seen.insert(key)
        note(yoloClass, for: a)
    }

    /// Top aisle once there are ≥ `minVotes` votes and it holds ≥ `minShare` of them. Ties break alphabetically.
    public func verdict(minVotes: Int = 6, minShare: Double = 0.6) -> String? {
        let total = self.total
        guard total >= minVotes, total > 0,
              let top = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
              Double(top.value) / Double(total) >= minShare else { return nil }
        return top.key
    }

    public func share(of aisle: String) -> Double {
        let total = self.total
        return total > 0 ? Double(counts[aisle] ?? 0) / Double(total) : 0
    }

    public func evidence(for aisle: String) -> [String] { evidence[aisle] ?? [] }

    public mutating func reset() { self = AisleVote() }

    private mutating func note(_ word: String, for aisle: String) {
        if !(evidence[aisle] ?? []).contains(word) { evidence[aisle, default: []].append(word) }
    }

    // MARK: - Maps from categories.json

    /// Normalized word → aisle from `productWords` (and `aisleWords`), plus each aisle key itself.
    /// A word listed by several aisles goes to the aisle named by it ("coffee" → coffee), else to the one aisle
    /// listing it among its `aisleWords`; otherwise it's ambiguous ("great value", "latte") and left out.
    public static func wordToAisle(_ catalog: [String: AisleInfo], includeAisleWords: Bool = true) -> [String: String] {
        var owners: [String: Set<String>] = [:]
        var signOwners: [String: Set<String>] = [:]
        for (aisle, info) in catalog {
            let key = normalizeText(aisle)
            if !key.isEmpty { owners[key, default: []].insert(aisle); signOwners[key, default: []].insert(aisle) }
            for w in info.productWords.map(normalizeText) where !w.isEmpty { owners[w, default: []].insert(aisle) }
            if includeAisleWords {
                for w in info.aisleWords.map(normalizeText) where !w.isEmpty {
                    owners[w, default: []].insert(aisle); signOwners[w, default: []].insert(aisle)
                }
            }
        }
        return resolve(owners, strong: signOwners)
    }

    /// YOLO class → aisle from `visualClasses` (ambiguous classes left out, as above).
    public static func classToAisle(_ catalog: [String: AisleInfo]) -> [String: String] {
        var owners: [String: Set<String>] = [:]
        for (aisle, info) in catalog {
            for c in info.visualClasses where !c.isEmpty { owners[c, default: []].insert(aisle) }
        }
        return resolve(owners, strong: [:])
    }

    private static func resolve(_ owners: [String: Set<String>], strong: [String: Set<String>]) -> [String: String] {
        var out: [String: String] = [:]
        for (word, aisles) in owners {
            if aisles.count == 1, let a = aisles.first { out[word] = a; continue }
            let n = normalizeText(word)
            if let named = aisles.first(where: { normalizeText($0) == n }) { out[word] = named; continue }
            if let s = strong[word], s.count == 1, let a = s.first { out[word] = a }
        }
        return out
    }
}

/// How a shelf-vote verdict relates to the goal's aisle (§5.7 wording is the flow's job).
public enum MatchingAisleRelation: Equatable {
    /// "This is the coffee aisle."
    case target
    /// "This looks like tea and cocoa. Coffee is usually nearby."
    case adjacent
    /// "This looks like cereal, not coffee."
    case different
    /// No verdict yet, or no target aisle (word search).
    case unsure
}

public func aisleRelation(verdict: String?, target: String?, catalog: [String: AisleInfo]) -> MatchingAisleRelation {
    guard let v = verdict, let t = target else { return .unsure }
    if v == t { return .target }
    if catalog[t]?.adjacent.contains(v) == true || catalog[v]?.adjacent.contains(t) == true { return .adjacent }
    return .different
}
