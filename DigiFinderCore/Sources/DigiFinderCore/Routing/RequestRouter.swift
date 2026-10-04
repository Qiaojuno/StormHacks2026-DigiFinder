// Offline request router (§5.2). One talk button: everything said goes through here.

public struct RequestRouter {
    /// Injected database search (app side); [] = no match.
    let productSearch: (String) -> [Goal]
    /// From synonyms.json.
    let destinations: [Destination: [String]]

    public init(productSearch: @escaping (String) -> [Goal], destinations: [Destination: [String]]) {
        self.productSearch = productSearch; self.destinations = destinations
    }

    // Phrases are in normalizeText form ("where's" → "where s").
    static let findPhrases = ["where", "find", "i need", "i want", "i d like", "get me", "looking for", "is there",
                              "do you have", "aisle", "take me", "bring me"]
    static let questionStarts = ["is this", "is it", "what", "does", "how much", "how many", "read", "which", "tell me", "can you"]
    /// Destination words that count only when said alone.
    static let aloneOnly: Set<String> = ["help", "information"]
    static let filler: Set<String> = ["the", "a", "an", "some", "please", "can", "you", "me", "i", "in", "is", "are",
        "what", "which", "aisle", "where", "s", "find", "need", "want", "get", "looking", "for", "there",
        "do", "have", "take", "bring", "to", "also", "add", "instead", "um", "uh", "d", "like", "ll", "help",
        "okay", "ok", "thanks", "thank", "yes", "yeah", "hello", "hi", "hey"]

    /// nil = not understood (empty or filler only).
    public func route(_ raw: String) -> Request? {
        let t = normalizeText(raw)
        guard !t.isEmpty else { return nil }
        if let cmd = VoiceCommandParser.parse(t) { return .command(cmd) }      // whole-utterance: "repeat", "switch", "add it", "where am i"
        for (d, words) in destinations {
            for w in words where (Self.aloneOnly.contains(w) ? t == w : has(t, w)) { return .destination(d) }
        }
        if has(t, "staff") { return .destination(.customerService) }
        let add = t.hasPrefix("also ") || t.hasPrefix("add ")
        var change: GoalChange = t.hasPrefix("actually ") || has(t, "instead") ? .replace : add ? .add : .unspecified
        let wantsToFind = change != .unspecified || t.hasPrefix("no ") || Self.findPhrases.contains { has(t, $0) }
        if !wantsToFind && Self.questionStarts.contains(where: { t.hasPrefix($0) }) {
            return .question(raw)                                              // "is this peanut butter crunchy?"
        }
        let whole = productQuery(t)
        guard !whole.isEmpty else { return nil }                               // "okay", "um"
        if let hit = search(whole) {                                           // whole phrase first: "mac and cheese"
            if hit.droppedNo { change = .replace }                             // "no, milk" = change of mind
            return .product(hit.goal, change)
        }
        let parts = t.components(separatedBy: " and ").map(productQuery).filter { !$0.isEmpty }
        if parts.count > 1 {
            let goals = parts.compactMap { search($0)?.goal }
            if goals.count == parts.count { return .products(goals) }
        }
        return .unknownProduct(whole, change)                                  // "toothpaste", "bathroom"
    }

    /// Try with a leading "no" first ("No Name peanut butter"), then without it ("no, milk instead").
    func search(_ q: String) -> (goal: Goal, droppedNo: Bool)? {
        if let g = productSearch(q).first { return (g, false) }
        if q.hasPrefix("no "), let g = productSearch(String(q.dropFirst(3))).first { return (g, true) }
        return nil
    }

    /// Whole words only.
    func has(_ t: String, _ phrase: String) -> Bool { " \(t) ".contains(" \(phrase) ") }

    func productQuery(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        if words.first == "actually" { words.removeFirst() }
        return words.filter { !Self.filler.contains($0) }.joined(separator: " ")
    }
}
