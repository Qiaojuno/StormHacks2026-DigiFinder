import Foundation
import DigiFinderCore

/// A product search over text in `normalizeText` form.
/// Every group must match; a group matches when any one of its phrases appears as whole, contiguous words.
/// The same query runs as FTS5, as LIKE (when FTS5 is missing) or in memory (`extraProducts`), with the same meaning.
struct DataSearchQuery: Equatable {
    private(set) var groups: [[String]] = []

    init() {}

    /// Plain words, all required: "dark roast" → dark AND roast.
    init(words text: String) {
        for word in normalizeText(text).split(separator: " ") { add([String(word)]) }
    }

    var isEmpty: Bool { groups.isEmpty }

    /// Only the first phrase of each group (the words as said), used to rank exact wording first.
    var primary: DataSearchQuery {
        var q = DataSearchQuery(); q.groups = groups.map { [$0[0]] }; return q
    }

    /// Adds one required group of alternative phrases. Phrases are normalized; empty ones and repeats are dropped.
    mutating func add(_ phrases: [String]) {
        var seen = Set<String>(), clean: [String] = []
        for p in phrases.map(normalizeText) where !p.isEmpty && seen.insert(p).inserted { clean.append(p) }
        if !clean.isEmpty { groups.append(clean) }
    }

    func adding(_ phrases: [String]) -> DataSearchQuery {
        var q = self; q.add(phrases); return q
    }

    /// FTS5 MATCH expression: ("a" OR "b c") AND ("d"). Phrases hold only a–z, 0–9 and spaces, so quoting is safe.
    var ftsExpression: String {
        groups.map { "(" + $0.map { "\"\($0)\"" }.joined(separator: " OR ") + ")" }.joined(separator: " AND ")
    }

    /// LIKE fallback over a space-padded column (whole words, like FTS5 on normalized text).
    func likeClause(column: String) -> (sql: String, args: [String]) {
        var args: [String] = []
        let sql = groups.map { group in
            "(" + group.map { phrase -> String in
                args.append("% \(phrase) %")
                return "(' ' || \(column) || ' ') LIKE ?"
            }.joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
        return (sql, args)
    }

    /// In-memory match against text already in `normalizeText` form.
    func matches(normalized text: String) -> Bool {
        let padded = " \(text) "
        return !groups.isEmpty && groups.allSatisfy { group in group.contains { padded.contains(" \($0) ") } }
    }
}
