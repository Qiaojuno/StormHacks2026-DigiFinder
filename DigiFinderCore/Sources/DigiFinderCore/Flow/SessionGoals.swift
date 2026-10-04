// Routed requests, goal queue, change of mind, unknown items, Ask, destinations and endings (§5.2, §5.6, §5.9–5.12).
import Foundation

// MARK: - Requests

extension ShoppingSession {
    mutating func handleRequest(_ r: Request) {
        if let pending = state.pendingChoice, resolveChoice(pending, with: r) { return }
        if state.askingNext {                                // anything said answers "What's next?"
            state.askingNext = false
            state.askingNextAt = nil
            if r == .command(.finishTalking) || r == .command(.stop) { finishShopping(); return }
        }
        if Self.changesTarget(r) {                       // a new target drops replies still pending for the old one
            state.lookup = nil
            state.surroundingsSince = nil
        }
        switch r {
        case .command(let c): command(c)
        case .destination(let d): beginDestination(d)
        case .product(let g, let change): applyGoal(g, change, announce: true)
        case .products(let goals): products(goals)
        case .unknownProduct(let words, let change): unknownProduct(words, change)
        case .question(let q): question(q)
        }
    }

    static func changesTarget(_ r: Request) -> Bool {
        switch r {
        case .command(.stop), .command(.thatsAll), .destination, .product, .products, .unknownProduct: return true
        default: return false
        }
    }

    mutating func notUnderstood(noisy: Bool) {
        if let pending = state.pendingChoice {               // no clear answer → add it
            clearChoice()
            enqueue(pending, line: SessionPhrases.willAdd(name(pending)))
            return
        }
        if state.askingNext {                                // silence after "What's next?" → done
            if noisy && !state.marks.noisyRetry {
                state.marks.noisyRetry = true
                reply(SessionPhrases.notCaughtNoisy, prompt: false)
                state.askingNextAt = state.now
                listen(SessionTuning.autoListenSeconds)
                return
            }
            finishShopping()
            return
        }
        reply(noisy ? SessionPhrases.notCaughtNoisy : SessionPhrases.notCaught, prompt: false)
    }

    // MARK: Switch or add (§5.2)

    /// Returns true when the request was only an answer to "Switch to milk, or add it?".
    mutating func resolveChoice(_ pending: Goal, with r: Request) -> Bool {
        clearChoice()
        switch r {
        case .command(.switchGoal):
            replaceGoal(pending, announce: true)
            return true
        case .command(.addGoal):
            enqueue(pending, line: SessionPhrases.added(name(pending)))
            return true
        case .command(.stop):                                // "never mind": keep the current goal
            reply(SessionPhrases.stillLooking(activeTargetName), prompt: false)
            return true
        case .product(let g, .replace) where g == pending:
            replaceGoal(pending, announce: true)
            return true
        case .product(let g, .add) where g == pending:
            enqueue(pending, line: SessionPhrases.added(name(pending)))
            return true
        default:
            enqueue(pending, line: SessionPhrases.willAdd(name(pending)))
            return r == .product(pending, .unspecified)
        }
    }

    mutating func askSwitchOrAdd(_ g: Goal) {
        state.pendingChoice = g
        state.choiceAskedAt = state.now
        reply(SessionPhrases.switchOrAdd(name(g)))
        listen(SessionTuning.autoListenSeconds)
    }

    mutating func clearChoice() {
        state.pendingChoice = nil
        state.choiceAskedAt = nil
    }

    // MARK: Goals and queue

    /// `announce: false` when an earlier line already introduced the goal (unknown items).
    mutating func applyGoal(_ g: Goal, _ change: GoalChange, announce: Bool) {
        if state.goal == g {
            if announce { reply(SessionPhrases.lookingFor(name(g))) }
            return
        }
        guard hasActiveGoal else {
            begin(g, line: announce ? SessionPhrases.lookingFor(name(g)) : nil)
            return
        }
        switch change {
        case .replace: replaceGoal(g, announce: announce)
        case .add: enqueue(g, line: SessionPhrases.added(name(g)))
        case .unspecified: askSwitchOrAdd(g)
        }
    }

    mutating func replaceGoal(_ g: Goal, announce: Bool) {
        state.goal = nil
        state.destination = nil
        begin(g, line: announce ? SessionPhrases.instead(name(g)) : nil)
    }

    mutating func enqueue(_ g: Goal, line: String) {
        if state.goal != g && !state.queue.contains(g) { state.queue.append(g) }
        reply(line)
    }

    mutating func products(_ goals: [Goal]) {
        guard let first = goals.first else { return }
        guard goals.count > 1 else { applyGoal(first, .unspecified, announce: true); return }
        let names = goals.map(name)
        if hasActiveGoal {
            for g in goals where state.goal != g && !state.queue.contains(g) { state.queue.append(g) }
            reply(SessionPhrases.added(SessionPhrases.list(names)))
        } else {
            begin(first, line: SessionPhrases.findFirst(names))
            for g in goals.dropFirst() where g != first && !state.queue.contains(g) { state.queue.append(g) }
        }
    }

    /// Start guiding to `g`: same aisle → straight to the shelf; outside → entrance; else → signs.
    mutating func begin(_ g: Goal, line: String?) {
        let sameAisle = standsInAisle(for: g)
        if state.step == .sessionDone { state.foundCount = 0 }
        state.goal = g
        state.destination = nil
        state.askingNext = false
        state.askingNextAt = nil
        state.queue.removeAll { $0 == g }
        state.goalEpoch += 1
        state.progress = SessionGoalProgress(evidenceAt: state.now)
        out.append(.setTarget(g, candidates: [], destination: nil))
        if let line { reply(line) }
        if sameAisle {
            announce(SessionPhrases.alsoInAisle(name(g)))
            enterPointing(prompt: false)
        } else if state.outside {
            enterEntrance()
        } else {
            enter(.findingSignage)
        }
    }

    /// Next queued goal, else "What's next?" + auto-listen.
    mutating func advanceToNext() {
        state.goal = nil
        state.destination = nil
        if !state.queue.isEmpty {
            let next = state.queue.removeFirst()
            announce(SessionPhrases.next(name(next)))
            begin(next, line: nil)
            return
        }
        state.goalEpoch += 1
        out.append(.setTarget(nil, candidates: [], destination: nil))
        enter(.askingGoal)
        state.askingNext = true
        state.askingNextAt = state.now
        announce(SessionPhrases.whatsNext)
        listen(SessionTuning.autoListenSeconds)
    }

    // MARK: Unknown items (§5.2)

    mutating func unknownProduct(_ words: String, _ change: GoalChange) {
        if state.online {
            reply(SessionPhrases.unknownOnline(words))
            out.append(.lookupProduct(words))
            state.lookup = SessionLookup(words: words, change: change, startedAt: state.now)
        } else {
            reply(SessionPhrases.unknownOffline(words))
            applyGoal(Goal(product: words), change, announce: false)
        }
    }

    /// Runner result of `.lookupProduct`: a goal with an aisle, a word-search goal (signWords), or nil.
    mutating func productLookedUp(_ found: Goal?) {
        guard let lookup = state.lookup else { return }
        state.lookup = nil
        if let g = found, let aisle = g.category {
            let starts = !hasActiveGoal || lookup.change == .replace
            reply(starts ? SessionPhrases.foundOnline(name(g), aisle: displayAisle(aisle)) : SessionPhrases.found(name(g)))
            applyGoal(g, lookup.change, announce: false)
        } else {
            var g = found ?? Goal(product: lookup.words)
            if g.product.trimmingCharacters(in: .whitespaces).isEmpty { g.product = lookup.words }
            g.category = nil
            reply(SessionPhrases.wordSearch)
            applyGoal(g, lookup.change, announce: false)
        }
    }

    // MARK: Ask (§5.11)

    mutating func question(_ q: String) {
        guard state.online else {
            reply(SessionPhrases.offlineQuestion, prompt: false)
            return
        }
        reply(SessionPhrases.checking, prompt: false)
        out.append(.ask(q))
        state.askStartedAt = state.now
        state.resumeStep = state.step
        state.step = .asking
        emitWork()
    }

    mutating func askAnswer(_ answer: String?) {
        guard state.step == .asking, state.askStartedAt != nil else { return }   // late answers are dropped
        state.askStartedAt = nil
        if let a = answer?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            reply(a)
            out.append(.chime(.done))
        } else {
            reply(SessionPhrases.noAnswer, prompt: false)
        }
        resumeAfterAsking()
    }

    mutating func resumeAfterAsking() {
        resumePausedStep()
        replayHeld()
        recalculate()
    }

    // MARK: Commands (§5.2, §5.9)

    mutating func command(_ c: VoiceCommand) {
        switch c {
        case .stop: stop()
        case .thatsAll: finishShopping()
        case .repeatLast:
            let text = state.lastPrompt.isEmpty ? (state.step == .askingGoal ? SessionPhrases.askGoal : state.lastLine) : state.lastPrompt
            reply(text, prompt: false)
        case .lessDetail:
            state.verbosity = Verbosity(rawValue: max(Verbosity.brief.rawValue, state.verbosity.rawValue - 1)) ?? .brief
            reply(SessionPhrases.shorter, prompt: false)
        case .moreDetail:
            state.verbosity = Verbosity(rawValue: min(Verbosity.detailed.rawValue, state.verbosity.rawValue + 1)) ?? .detailed
            reply(SessionPhrases.moreDetail, prompt: false)
        case .whatsAround:
            out.append(.describeSurroundings)
            state.surroundingsSince = state.now
        case .outside(let isOutside): setOutside(isOutside, saidByUser: true)
        case .finishTalking: break                           // "done": nothing more to do; resume
        case .switchGoal, .addGoal: reply(SessionPhrases.notCaught, prompt: false)   // nothing to switch to
        }
    }

    /// "What's around?" answer, then straight back to the current step.
    mutating func surroundings(_ text: String) {
        guard state.surroundingsSince != nil else { return }
        state.surroundingsSince = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        reply(t.isEmpty ? SessionPhrases.nothingAround : t)
        recalculate()
    }

    // MARK: Destinations (§5.6)

    mutating func beginDestination(_ d: Destination) {
        if let g = state.goal {                              // items on the list stay queued
            state.queue.removeAll { $0 == g }
            state.queue.insert(g, at: 0)
        }
        state.goal = nil
        state.destination = d
        state.askingNext = false
        state.askingNextAt = nil
        state.goalEpoch += 1
        state.progress = SessionGoalProgress(evidenceAt: state.now)
        out.append(.setTarget(nil, candidates: [], destination: d))
        switch d {
        case .customerService:
            reply(SessionPhrases.toCustomerService)
        case .checkout:
            let left = state.queue.isEmpty ? "" : " " + SessionPhrases.stillOnList(state.queue.map(name))
            reply(SessionPhrases.goingToCheckout + left)
        }
        if state.outside { enterEntrance() } else { enter(.findingDestination) }
    }

    mutating func arrivedAtDestination() {
        guard state.step == .findingDestination, let d = state.destination else { return }
        announce(d == .checkout ? SessionPhrases.atCheckout : SessionPhrases.atCustomerService)
        if !state.queue.isEmpty { announce(SessionPhrases.stillOnList(state.queue.map(name))) }
        out.append(.chime(.done))
        state.destination = nil
        state.goalEpoch += 1
        out.append(.setTarget(nil, candidates: [], destination: nil))
        enter(.idle)
    }

    // MARK: Endings (§5.12)

    mutating func stop() {
        if hasActiveGoal {
            reply(SessionPhrases.stopped, prompt: false)
            out.append(.chime(.done))
            advanceToNext()
        } else if state.foundCount > 0 {
            finishShopping()
        } else {
            reply(SessionPhrases.stopped, prompt: false)
            out.append(.chime(.done))
            enter(.idle)
        }
    }

    mutating func notFound() {
        announce(SessionPhrases.notFound)
        out.append(.chime(.done))
        advanceToNext()
    }

    mutating func pauseLost() {
        announce(SessionPhrases.guidancePaused)
        out.append(.chime(.done))
        state.resumeStep = state.step
        state.step = .paused
        state.pauseReason = .lost
        emitWork()
    }

    mutating func finishShopping() {
        announce(SessionPhrases.shoppingDone(state.foundCount))
        out.append(.chime(.done))
        state.goal = nil
        state.destination = nil
        state.queue = []
        clearChoice()
        state.askingNext = false
        state.askingNextAt = nil
        state.lookup = nil
        state.goalEpoch += 1
        out.append(.setTarget(nil, candidates: [], destination: nil))
        enter(.sessionDone)
    }
}

// MARK: - Names

extension ShoppingSession {
    /// Spoken goal name from the user's words: "Starbucks dark roast, whole bean".
    func name(_ g: Goal) -> String {
        var parts: [String] = []
        func add(_ s: String?) {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return }
            let n = normalizeText(s)
            guard !SessionText.has(normalizeText(parts.joined(separator: " ")), n) else { return }
            parts.removeAll { SessionText.has(n, normalizeText($0)) }      // "No Name" + "No Name peanut butter"
            parts.append(s)
        }
        add(g.brand)
        g.variant.forEach { add($0) }
        add(g.product)
        var text = parts.joined(separator: " ")
        if let f = g.form?.trimmingCharacters(in: .whitespaces), !f.isEmpty, !SessionText.has(normalizeText(text), normalizeText(f)) {
            text += ", \(f)"
        }
        return text.isEmpty ? g.product : text
    }

    /// What the signs call the goal: the product when it's a sign word ("peanut butter"), else the aisle ("coffee").
    func aisleName(_ g: Goal) -> String {
        guard let c = g.category else { return g.product }
        let words = (catalog[c]?.aisleWords ?? []).map(normalizeText)
        return words.contains(normalizeText(g.product)) ? g.product : displayAisle(c)
    }

    func displayAisle(_ key: String) -> String { key.replacingOccurrences(of: "_", with: " ") }

    var activeTargetName: String {
        if let g = state.goal { return name(g) }
        switch state.destination {
        case .checkout?: return "the checkout"
        case .customerService?: return "customer service"
        case nil: return "it"
        }
    }

    func productName(_ p: ProductInfo) -> String {
        guard let b = p.brand?.trimmingCharacters(in: .whitespaces), !b.isEmpty,
              !SessionText.has(normalizeText(p.name), normalizeText(b)) else { return p.name }
        return "\(b) \(p.name)"
    }

    /// The most specific thing the user asked for ("whole bean" in "That's ground, not whole bean.").
    func goalDetail(_ g: Goal) -> String {
        if let f = g.form, !f.isEmpty { return f }
        if !g.variant.isEmpty { return g.variant.joined(separator: " ") }
        if let b = g.brand, !b.isEmpty { return b }
        return g.product
    }

    /// Coffee and tea share a sign (each lists the other in aisleWords), so "Tea is in this aisle too."
    func sharesAisle(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let wa = (catalog[a]?.aisleWords ?? []).map(normalizeText)
        let wb = (catalog[b]?.aisleWords ?? []).map(normalizeText)
        return wa.contains(normalizeText(b)) || wb.contains(normalizeText(a))
    }

    func standsInAisle(for g: Goal) -> Bool {
        guard let here = state.currentAisle, let there = g.category else { return false }
        let atShelf = [.walkingAisle, .pointing, .holdUpToCheck, .askingGoal].contains(state.step)   // askingGoal: "What's next?" at the shelf
        return atShelf && sharesAisle(here, there)
    }
}

enum SessionText {
    /// Whole-word containment on normalizeText output.
    static func has(_ text: String, _ phrase: String) -> Bool {
        !phrase.isEmpty && " \(text) ".contains(" \(phrase) ")
    }
}
