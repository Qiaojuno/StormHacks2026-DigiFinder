// Pick (pointing), Confirm (hold-up check) and add to cart (§5.2).
import Foundation

extension ShoppingSession {
    mutating func pointed(_ p: PointedProduct?) {
        guard state.step == .pick, let p else { return }
        let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if p.match >= SessionTuning.pointMatch {
            state.progress.lastMatchAt = state.now
            noteEvidence()
            enter(.confirm)
            announce(p.alternative.map { SessionPhrases.grabWithAlternative(text, $0) } ?? SessionPhrases.grab(text))
            announce(SessionPhrases.holdUp)
            return
        }
        if p.match >= SessionTuning.nearMiss { noteEvidence() }
        // "That's Pike Place. Move right." at most once per second.
        if let last = state.marks.lastPointCueAt, state.now - last < SessionTuning.pointCueInterval { return }
        let line = p.directionToTarget.map { SessionPhrases.thatsMove(text, $0) } ?? SessionPhrases.notItMoveRight
        if guide(line, dedupe: true, repeatAfter: SessionTuning.pointRepeat) { state.marks.lastPointCueAt = state.now }
    }

    /// "The shelf is about one step ahead." once per Pick; closer than ~0.3 m is "Step back a little" (§5.8).
    mutating func shelfDistance(_ meters: Float) {
        guard state.step == .pick, !state.marks.shelfDistanceSaid, meters.isFinite, meters >= 0.3, meters <= 4,
              !guidanceHeld else { return }
        state.marks.shelfDistanceSaid = true
        narrate(SessionPhrases.shelfAhead(meters))
    }

    /// Label check on the held item. nil = unclear (the hold-up timers prompt).
    mutating func confirmed(_ info: ProductInfo?, isGoal: Bool) {
        guard let goal = state.goal, let info else { return }
        switch state.step {
        case .confirm: break
        case .pick where isGoal: break                      // a visible barcode wins
        default: return
        }
        noteEvidence()
        state.progress.lastMatchAt = state.now
        let product = productName(info)
        guard isGoal else {
            if !state.onDeviceItemSearch {
                // Gemini mode: put it back and search again (Gemini guides to the right one).
                enter(state.pickReturn)
                announce(SessionPhrases.wrongItem(SessionPhrases.capWords("That's \(product), not \(name(goal)).")))
                recalculate()
                return
            }
            enter(.pick)                                    // back to pointing (voice only, no haptics)
            announce(SessionPhrases.wrongItem(wrongItemLine(found: info, goal: goal)))
            return
        }
        if !state.onDeviceItemSearch {
            announce(SessionPhrases.gotIt(name(goal)))
            out.append(.chime(.done))
            out.append(.markDone(goal))
            state.foundCount += 1
            advanceToNext()
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

    /// Confirm in Gemini mode (owner decision): never gives up. Nothing held → "Pick it up and hold it out." every
    /// ~10 s; walking ~4 s without holding it → back to the search (the next sighting brings it back here).
    mutating func holdTimers() {
        let now = state.now
        if state.isWalking {
            let since = state.marks.confirmWalkSince ?? now
            state.marks.confirmWalkSince = since
            if now - since >= SessionTuning.confirmWalkAway {
                enter(state.pickReturn)
                recalculate()
            }
            return
        }
        state.marks.confirmWalkSince = nil
        if now - (state.marks.holdPromptAt ?? now) >= SessionTuning.holdReminder, guide(SessionPhrases.pickUpHold) {
            state.marks.holdPromptAt = now
        }
    }

    /// Pick / Confirm: ~90 s since entering the aisle with no match → not found (§5.12).
    mutating func notFoundTimer() {
        guard let entered = state.progress.aisleEnteredAt else { return }
        let anchor = max(entered, state.progress.lastMatchAt ?? entered)
        if state.now - anchor >= SessionTuning.notFound { notFound() }
    }
}
