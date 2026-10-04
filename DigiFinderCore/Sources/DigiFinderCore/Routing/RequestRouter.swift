// Offline request router (§5.2). One talk button: everything said goes through here.
//
// Rule, in order:
// 1. Commands (whole utterance), then destinations ("help" / "information" only when said alone).
// 2. No find phrasing and starts with question phrasing → question.
// 3. Database match on the whole phrase first; else split on " and " / "then" / "plus" and every part must match.
//    A leading "no" is dropped only if the phrase doesn't match with it ("No Name peanut butter" keeps its brand).
//    A failed search is retried with catalog synonyms ("pb" → "peanut butter").
// 4. Anything left with real words → unknown item. Nothing left (only filler) → not understood (nil).

/// The routed request plus the goal change the words implied. `Request.products` has no change slot, so callers
/// that need "actually coffee and milk" (replace both) read `change` here (see CONTRACT_CHANGES.md).
public struct RoutingResult: Equatable {
    public var request: Request?
    public var change: GoalChange
    public init(request: Request?, change: GoalChange = .unspecified) { self.request = request; self.change = change }
}

public struct RequestRouter {
    /// Injected database search (app side); [] = no match.
    let productSearch: (String) -> [Goal]
    /// From synonyms.json `destinations`.
    let destinations: [Destination: [String]]
    /// From synonyms.json `synonyms`.
    let synonyms: MatchingSynonyms

    public init(productSearch: @escaping (String) -> [Goal], destinations: [Destination: [String]],
                synonyms: [String: [String]] = [:]) {
        self.productSearch = productSearch; self.destinations = destinations
        self.synonyms = MatchingSynonyms(synonyms)
    }

    // Phrases are in normalizeText form ("where's" → "where s").
    static let findPhrases = ["where", "find", "i need", "we need", "i want", "i wanna", "i d like", "i would like",
                              "get me", "can i get", "looking for", "look for", "search for", "searching for", "locate",
                              "is there", "are there", "do you have", "do you sell", "do you carry", "got any", "aisle",
                              "take me", "bring me", "show me", "lead me", "guide me", "go to", "get to", "pick up"]
    static let questionStarts = ["is this", "is it", "is that", "are these", "are they", "are those", "what", "does",
                                 "do these", "do they", "do i", "how", "read", "which", "tell me", "can you", "could you",
                                 "would you", "can i", "should i", "who", "why", "when", "describe", "explain",
                                 "check if", "check whether", "check the", "has this", "will"]
    /// Destination words that count only when said alone.
    static let aloneOnly: Set<String> = ["help", "information"]
    /// Words allowed around an alone-only destination word: "I need help", "can someone help me".
    static let aloneCompanions: Set<String> = ["please", "i", "need", "me", "can", "could", "you", "someone", "somebody",
        "some", "get", "want", "hey", "okay", "ok", "um", "uh", "oh", "is", "there", "any", "anyone", "the", "a", "for",
        "go", "to", "take", "bring", "find", "where", "s", "we", "us", "with", "desk"]
    /// Built-in destination phrases on top of synonyms.json.
    static let extraDestinations: [Destination: [String]] = [
        .customerService: ["staff", "employee", "store employee", "worker", "associate", "someone who works here",
                           "somebody who works here", "talk to someone", "talk to a person", "speak to someone",
                           "service desk", "help desk", "information desk", "customer care", "manager"],
        .checkout: ["checkouts", "check out", "self check out", "cashier", "cash register", "register",
                    "where do i pay", "where can i pay", "ready to pay", "want to pay", "pay for my"],
    ]
    /// Said first: replace the current goal ("actually X", "switch to X", "never mind, X").
    static let replacePrefixes = ["actually", "switch to", "change to", "change it to", "make it", "make that", "i meant",
                                  "i mean", "scratch that", "never mind", "forget it", "forget that", "cancel that"]
    /// Discourse filler dropped from the front before the question test ("um is this gluten free").
    static let leadingFiller: Set<String> = ["um", "uh", "er", "erm", "hmm", "okay", "ok", "so", "oh", "hey", "well",
                                             "and", "please", "sorry", "excuse", "alright", "yeah", "yes"]
    /// Multi-word phrases removed before single filler words ("pick up" keeps "7 up" intact).
    static let fillerPhrases: [[String]] = [
        "pick up", "as well", "to the list", "to my list", "on the list", "on my list", "to the cart", "to my cart",
        "excuse me", "how do i get to", "scratch that", "never mind", "forget it", "forget that", "cancel that",
    ].map { $0.split(separator: " ").map(String.init) }
    static let filler: Set<String> = ["the", "a", "an", "some", "please", "can", "you", "me", "i", "in", "is", "are",
        "what", "which", "aisle", "where", "s", "find", "need", "want", "get", "looking", "for", "there",
        "do", "have", "take", "bring", "to", "also", "add", "instead", "um", "uh", "d", "like", "ll", "help",
        "okay", "ok", "thanks", "thank", "yes", "yeah", "hello", "hi", "hey",
        // additions
        "could", "would", "tell", "show", "know", "let", "us", "we", "my", "our", "go", "going", "got", "gonna", "wanna",
        "gotta", "grab", "look", "search", "searching", "locate", "located", "location", "lead", "guide", "it", "this",
        "that", "these", "those", "here", "near", "nearest", "closest", "section", "area", "shelf", "shelves",
        "department", "item", "items", "product", "products", "something", "any", "anything", "your", "on", "at",
        "has", "carry", "sell", "stock", "kept", "keep", "too", "er", "erm", "hmm", "so", "oh", "well", "just",
        "really", "actually", "m", "am", "re", "ve", "list", "cart", "now", "first", "next", "sorry", "excuse",
        "switch", "change", "make", "meant", "mean", "rather", "nope", "alright"]

    /// nil = not understood (empty or filler only).
    public func route(_ raw: String) -> Request? { routeWithChange(raw).request }

    /// Same as `route`, plus the goal change implied by the words (also for multi-product requests).
    public func routeWithChange(_ raw: String) -> RoutingResult {
        let t = normalizeText(raw)
        guard !t.isEmpty else { return RoutingResult(request: nil) }
        if let cmd = VoiceCommandParser.parse(t) { return RoutingResult(request: .command(cmd)) }   // "repeat", "switch", "add it"
        if let d = destination(t) { return RoutingResult(request: .destination(d)) }
        let core = Self.dropLeadingFiller(t)
        var change = goalChange(core)
        let wantsToFind = change != .unspecified || startsWith(core, "no") || Self.findPhrases.contains { has(core, $0) }
        if !wantsToFind && Self.questionStarts.contains(where: { startsWith(core, $0) }) {
            return RoutingResult(request: .question(raw))                                         // "is this peanut butter crunchy?"
        }
        let whole = productQuery(core)
        guard !whole.isEmpty, whole != "no" else { return RoutingResult(request: nil) }          // "okay", "um"
        if let hit = search(whole) {                                                              // whole phrase first: "mac and cheese"
            if hit.droppedNo { change = .replace }                                                // "no, milk" = change of mind
            return RoutingResult(request: .product(hit.goal, change), change: change)
        }
        let parts = Self.splitList(core).map(productQuery).filter { !$0.isEmpty && $0 != "no" }
        if parts.count > 1 {
            let hits = parts.compactMap { search($0) }
            if hits.count == parts.count {
                if hits.first?.droppedNo == true { change = .replace }
                return RoutingResult(request: .products(hits.map(\.goal)), change: change)
            }
        }
        return RoutingResult(request: .unknownProduct(whole, change), change: change)              // "toothpaste", "bathroom"
    }

    /// Goal change implied by the words: "actually X" / "X instead" / "switch to X" → replace;
    /// "also X" / "add X" / "X too" / "X as well" → add.
    public func goalChange(_ normalized: String) -> GoalChange {
        let t = Self.dropLeadingFiller(normalized)
        if Self.replacePrefixes.contains(where: { startsWith(t, $0) }) || has(t, "instead") || has(t, "rather") { return .replace }
        if startsWith(t, "also") || startsWith(t, "add") || has(t, "also") || has(t, "add")
            || t.hasSuffix(" too") || t.hasSuffix(" as well") { return .add }
        return .unspecified
    }

    /// Try with a leading "no" first ("No Name peanut butter"), then without it ("no, milk instead").
    /// Each try falls back to catalog synonyms ("pb" → "peanut butter").
    func search(_ q: String) -> (goal: Goal, droppedNo: Bool)? {
        if let g = searchWithSynonyms(q) { return (g, false) }
        if startsWith(q, "no"), q.count > 3, let g = searchWithSynonyms(String(q.dropFirst(3))) { return (g, true) }
        return nil
    }

    private func searchWithSynonyms(_ q: String) -> Goal? {
        if let g = productSearch(q).first { return g }
        for alt in synonyms.alternatives(for: q).dropFirst() {
            if let g = productSearch(alt).first { return g }
        }
        return nil
    }

    /// Longest matching destination phrase; synonyms.json first, then the built-in phrases. Deterministic.
    func destination(_ t: String) -> Destination? {
        var best: (d: Destination, len: Int)?
        for source in [destinations, Self.extraDestinations] {
            for d in source.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                for raw in source[d] ?? [] {
                    let w = normalizeText(raw)
                    guard !w.isEmpty else { continue }
                    let hit = Self.aloneOnly.contains(w) ? isAlone(t, w) : has(t, w)
                    if hit, best == nil || w.count > best!.len { best = (d, w.count) }
                }
            }
            if best != nil { return best?.d }
        }
        return nil
    }

    /// "help", "I need help", "can someone help me", but not "help me find peanut butter".
    func isAlone(_ t: String, _ w: String) -> Bool {
        if t == w { return true }
        guard has(t, w) else { return false }
        let rest = replacePhrase(in: t, w, with: "").split(separator: " ").map(String.init)
        return rest.allSatisfy(Self.aloneCompanions.contains)
    }

    /// Whole words only.
    func has(_ t: String, _ phrase: String) -> Bool { containsPhrase(t, phrase) }

    /// Whole-word prefix: "read the label" starts with "read", "ready to pay" doesn't.
    func startsWith(_ t: String, _ phrase: String) -> Bool { t == phrase || t.hasPrefix(phrase + " ") }

    func productQuery(_ s: String) -> String {
        var words = Self.dropLeadingFiller(s).split(separator: " ").map(String.init)
        for p in Self.replacePrefixes.map({ $0.split(separator: " ").map(String.init) })
        where words.count >= p.count && Array(words.prefix(p.count)) == p {
            words.removeFirst(p.count)
            break
        }
        words = Self.removePhrases(words, Self.fillerPhrases)
        return words.filter { !Self.filler.contains($0) }.joined(separator: " ")
    }

    static func dropLeadingFiller(_ t: String) -> String {
        var words = t.split(separator: " ").map(String.init)
        while words.count > 1, let f = words.first, leadingFiller.contains(f) {
            words.removeFirst()
            if f == "excuse", words.first == "me" { words.removeFirst() }
        }
        return words.joined(separator: " ")
    }

    static func removePhrases(_ words: [String], _ phrases: [[String]]) -> [String] {
        var out: [String] = []
        var i = 0
        outer: while i < words.count {
            for p in phrases where i + p.count <= words.count && Array(words[i..<i + p.count]) == p {
                i += p.count
                continue outer
            }
            out.append(words[i]); i += 1
        }
        return out
    }

    /// Splits a list: "coffee and milk", "coffee then milk", "coffee and also milk", "coffee plus milk".
    static func splitList(_ t: String) -> [String] {
        let separators: [[String]] = [["and", "then"], ["and", "also"], ["as", "well", "as"], ["and"], ["then"], ["plus"]]
        let words = t.split(separator: " ").map(String.init)
        var parts: [[String]] = [[]]
        var i = 0
        outer: while i < words.count {
            for s in separators where i + s.count <= words.count && Array(words[i..<i + s.count]) == s {
                parts.append([]); i += s.count
                continue outer
            }
            parts[parts.count - 1].append(words[i]); i += 1
        }
        return parts.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }
}
