// Pointing, hold-up check and add to cart (§5.2 "Point at the shelf" → "Confirm and add to cart").
import Foundation

extension ShoppingSession {
    mutating func pointed(_ p: PointedProduct?) {
        guard state.step == .pointing, let p else { return }
        let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if p.match >= SessionTuning.pointMatch {
            state.progress.lastMatchAt = state.now
            noteEvidence()
            announce(p.alternative.map { SessionPhrases.grabWithAlternative(text, $0) } ?? SessionPhrases.grab(text))
            announce(SessionPhrases.holdUp)
            enter(.holdUpToCheck)
            return
        }
        if p.match >= SessionTuning.nearMiss { noteEvidence() }
        // "That's Pike Place. Move right." at most once per second.
        if let last = state.marks.lastPointCueAt, state.now - last < SessionTuning.pointCueInterval { return }
        let line = p.directionToTarget.map { SessionPhrases.thatsMove(text, $0) } ?? SessionPhrases.notItMoveRight
        if guide(line, dedupe: true, repeatAfter: SessionTuning.pointRepeat) { state.marks.lastPointCueAt = state.now }
    }

    /// Label check on the held item. nil = unclear (the hold-up timers prompt).
    mutating func confirmed(_ info: ProductInfo?, isGoal: Bool) {
        guard let goal = state.goal, let info else { return }
        switch state.step {
        case .holdUpToCheck: break
        case .pointing where isGoal: break                  // a visible barcode wins
        default: return
        }
        noteEvidence()
        state.progress.lastMatchAt = state.now
        let product = productName(info)
        guard isGoal else {
            announce(SessionPhrases.wrongItem(product, not: goalDetail(goal)))
            enterPointing(prompt: false)
            return
        }
        // Word search has no database candidates: read the label back.
        announce(goal.category == nil ? SessionPhrases.thisSays(product) : SessionPhrases.gotIt(product))
        out.append(.chime(.done))
        out.append(.remember(info))
        out.append(.markDone(goal))
        state.foundCount += 1
        advanceToNext()
    }

    /// Unclear ~4 s → "Turn it slowly." ~8 s → "Try holding it a little farther away." (then again).
    mutating func unclearTimers() {
        let since = state.now - state.marks.unclearAnchor
        if state.marks.unclearStage == 0 {
            if since >= SessionTuning.unclearTurn, guide(SessionPhrases.turnItSlowly) { state.marks.unclearStage = 1 }
        } else if since >= SessionTuning.unclearFarther, guide(SessionPhrases.holdFarther) {
            state.marks.unclearStage = 0
            state.marks.unclearAnchor = state.now
        }
    }

    /// ~90 s in the right aisle with no match → not found (§5.12).
    mutating func notFoundTimer() {
        guard let entered = state.progress.aisleEnteredAt else { return }
        let anchor = max(entered, state.progress.lastMatchAt ?? entered)
        if state.now - anchor >= SessionTuning.notFound { notFound() }
    }
}
