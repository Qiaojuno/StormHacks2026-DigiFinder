// Entrance, signage, shelf vote, aisle arrival and destination signs (§5.2, §5.6, §5.7).

// MARK: - Inside / outside and the entrance (P1)

extension ShoppingSession {
    mutating func setOutside(_ isOutside: Bool, saidByUser: Bool) {
        let changed = state.outside != isOutside
        state.outside = isOutside
        if isOutside {
            guard changed || saidByUser, hasActiveGoal,
                  state.step == .findingSignage || state.step == .findingDestination else { return }
            enterEntrance()
        } else if state.step == .findingEntrance {
            announce(SessionPhrases.inside)
            enter(state.goal != nil ? .findingSignage : state.destination != nil ? .findingDestination : .idle)
        }
    }

    mutating func enterEntrance() {
        enter(.findingEntrance)
        state.entrance = SessionEntranceState(online: state.online)
        announce(SessionPhrases.lookingForEntrance)
        if state.online { requestPick() }
    }

    mutating func requestPick() {
        out.append(.pickEntrance)
        state.entrance.tries += 1
        state.entrance.lastPickAt = state.now
        state.entrance.awaitingPick = true
        state.entrance.waitingForTurn = false
    }

    mutating func entrancePicked(_ pick: EntrancePick?) {
        guard state.step == .findingEntrance, state.entrance.online else { return }
        state.entrance.awaitingPick = false
        guard let p = pick else {
            if state.entrance.tries >= SessionTuning.maxPicks {    // give up on photos: door signs instead
                state.entrance.online = false
                return
            }
            guide(SessionPhrases.cantSeeEntrance)
            state.entrance.waitingForTurn = true                  // ask again after a ~60° turn
            state.entrance.yawAtFail = state.yaw
            return
        }
        let degrees = Geometry.degreesRight(portraitX: p.x, horizontalFOV: SessionTuning.stillHorizontalFOV)
        state.entrance.bearing = state.yaw + degrees
        state.entrance.lastTrackedAt = state.now
        state.entrance.tries = 0
        guard !state.entrance.pickAnnounced else { return }       // say it once
        state.entrance.pickAnnounced = true
        announce(SessionPhrases.entranceAt(clockPosition(degreesRight: degrees), kind: p.kind))
        if let corral = p.cartCorralX {
            let c = clockPosition(degreesRight: Geometry.degreesRight(portraitX: corral, horizontalFOV: SessionTuning.stillHorizontalFOV))
            narrate(SessionPhrases.cartCorral(c))
        }
        if state.verbosity == .detailed, let note = p.note, !note.isEmpty { narrate(note) }
    }

    mutating func doorsSeen(_ doors: [DoorObservation]) {
        guard state.step == .findingEntrance, !doors.isEmpty else { return }
        state.entrance.lastDoorAt = state.now
        if state.entrance.online {
            guard let picked = state.entrance.bearing else { return }           // waiting for the pick
            let yaw = state.yaw
            let off = { (d: DoorObservation) in abs(SessionGeometry.angle(yaw + SessionGeometry.degrees(forClock: d.clock), from: picked)) }
            guard let best = doors.min(by: { off($0) < off($1) }), off(best) <= SessionTuning.doorTrackDegrees else { return }
            state.entrance.bearing = bearing(of: best)
            state.entrance.lastTrackedAt = state.now
            announceEntranceAhead(best)
            return
        }
        let byDistance = doors.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
        if let e = byDistance.first(where: { $0.label == .entrance }) {
            if state.entrance.sightingSaid { announceEntranceAhead(e); return }
            state.entrance.sightingSaid = true
            if let d = e.distance, d <= SessionTuning.entranceAnnounceMeters {
                announceEntranceAhead(e)
            } else {
                announce(SessionPhrases.entranceAt(e.clock, kind: .unknown))
            }
            return
        }
        let nearest = byDistance[0]
        if nearest.label == .exit, let other = byDistance.first(where: { $0.label != .exit }) {
            guide(SessionPhrases.exitDoor(otherClock: other.clock), dedupe: true)
            return
        }
        if nearest.label == .unknown, !state.entrance.noSignSaid {     // no sign on any door: nearest, honestly
            state.entrance.noSignSaid = true
            announce(SessionPhrases.doorNoSign(clock: nearest.clock, distance: nearest.distance))
        }
    }

    /// Once, within ~8 m: "Entrance ahead, about 7 meters, 12 o'clock."
    mutating func announceEntranceAhead(_ d: DoorObservation) {
        guard !state.entrance.aheadSaid, let m = d.distance, m <= SessionTuning.entranceAnnounceMeters else { return }
        state.entrance.aheadSaid = true
        announce(SessionPhrases.entranceAhead(m, clock: d.clock))
    }

    func bearing(of d: DoorObservation) -> Double { state.yaw + SessionGeometry.degrees(forClock: d.clock) }

    mutating func entranceTimers() {
        let e = state.entrance
        let now = state.now
        if e.online, state.online, !e.waitingForTurn {
            let sincePick = now - (e.lastPickAt ?? -Double.infinity)
            if e.awaitingPick {
                if sincePick >= SessionTuning.pickTimeout { state.entrance.awaitingPick = false }
            } else if e.tries < SessionTuning.maxPicks, sincePick >= SessionTuning.pickInterval,
                      e.bearing == nil || now - (e.lastTrackedAt ?? now) >= SessionTuning.doorLost {
                requestPick()                                   // lost the door (or no answer): new photo
            }
        }
        if !e.noDoorSaid, now - (e.lastDoorAt ?? state.stepStartedAt) >= SessionTuning.noDoor,
           guide(SessionPhrases.noDoor) {
            state.entrance.noDoorSaid = true
        }
    }

    mutating func entranceTurned() {
        let e = state.entrance
        guard e.online, state.online, e.waitingForTurn, let y0 = e.yawAtFail,
              abs(SessionGeometry.angle(state.yaw, from: y0)) >= SessionTuning.reaskTurnDegrees,
              state.now - (e.lastPickAt ?? -Double.infinity) >= SessionTuning.pickInterval else { return }
        requestPick()
    }
}

// MARK: - Signs

extension ShoppingSession {
    mutating func signsSeen(_ signs: [AisleSign]) {
        guard state.step != .paused else { return }
        let flowStep = state.step == .asking ? (state.resumeStep ?? .idle) : state.step
        let navigating = flowStep == .findingSignage || flowStep == .shelfVote
        if canObserve, !signs.isEmpty { state.marks.lastAnySignAt = state.now }

        // While the user talks, a target sign is still remembered (its bearing), just not spoken.
        if let goal = state.goal, navigating, let hit = targetSign(in: signs, words: navigationWords(goal), goal: goal) {
            rememberTargetSign(hit.sign)
            guard canObserve else { return }
            if state.step == .shelfVote { enter(.findingSignage) }     // a readable sign overrides the vote
            signDirection(hit.sign, word: hit.word)
            return
        }
        guard canObserve else { return }
        switch state.step {
        case .walkingAisle:
            guard let goal = state.goal, state.marks.turnBearing == nil,
                  let hit = targetSign(in: signs.filter { $0.number == nil }, words: shelfWords(goal), goal: goal) else { return }
            noteEvidence()
            announce(SessionPhrases.shelfAt(hit.word, clock: hit.sign.clock))
            enterPointing(prompt: true)
        case .findingDestination:
            if let d = state.destination { destinationSigns(signs, d) }
        case .findingSignage:
            if let goal = state.goal, !signs.isEmpty { otherSigns(signs, goal: goal) }
        default:
            break
        }
    }

    /// "9 o'clock, aisle 6, coffee and tea." when it changes, at most every ~2 s.
    mutating func signDirection(_ sign: AisleSign, word: String) {
        if let last = state.marks.lastDirectionAt, state.now - last < SessionTuning.directionInterval { return }
        let line = SessionPhrases.signDirection(clock: sign.clock, number: sign.number, words: sign.words,
                                                brief: state.verbosity == .brief, target: word)
        if guide(line, dedupe: true) { state.marks.lastDirectionAt = state.now }
    }

    /// Signs in view, none for the goal.
    mutating func otherSigns(_ signs: [AisleSign], goal: Goal) {
        if let last = state.marks.lastOtherSignsAt, state.now - last < SessionTuning.otherSignsInterval { return }
        let name = aisleName(goal)
        let line: String
        if signs.allSatisfy({ $0.words.isEmpty }), let s = signs.first {
            line = SessionPhrases.signAt(s.clock)
        } else if let memory = state.progress.signMemory {
            line = SessionPhrases.remembered(name, number: memory.number, clock: relativeClock(memory.bearing))
        } else {
            line = SessionPhrases.notOnSigns(name)
        }
        if guide(line, dedupe: true) { state.marks.lastOtherSignsAt = state.now }
    }

    mutating func rememberTargetSign(_ sign: AisleSign) {
        state.progress.signMemory = SessionSignMemory(number: sign.number, words: sign.words,
                                                      bearing: state.yaw + SessionGeometry.degrees(forClock: sign.clock))
        state.progress.lastTargetSignAt = state.now
        noteEvidence()
    }

    func relativeClock(_ bearing: Double) -> Int {
        clockPosition(degreesRight: SessionGeometry.angle(bearing, from: state.yaw))
    }

    /// Words that put a sign on the way: aisle sign words, the goal's words, and signWords for word search.
    func navigationWords(_ g: Goal) -> [String] {
        var words = [g.product] + g.synonyms + g.signWords
        if let c = g.category { words += [displayAisle(c)] + (catalog[c]?.aisleWords ?? []) }
        return unique(words.map(normalizeText).filter { !$0.isEmpty })
    }

    /// Shelf labels inside the aisle: only the goal's own words (not the neighbours sharing its sign).
    func shelfWords(_ g: Goal) -> [String] {
        var words = [g.product] + g.synonyms + g.signWords
        if let c = g.category { words.append(displayAisle(c)) }
        return unique(words.map(normalizeText).filter { !$0.isEmpty })
    }

    /// First sign naming one of `words` (in order of preference) and the word it named.
    func targetSign(in signs: [AisleSign], words: [String], goal: Goal) -> (sign: AisleSign, word: String)? {
        for w in words {
            for s in signs {
                let sw = s.words.map(normalizeText)
                if sw.contains(where: { SessionText.has($0, w) }) || SessionText.has(sw.joined(separator: " "), w) {
                    return (s, w == normalizeText(goal.product) ? goal.product : w)
                }
            }
        }
        return nil
    }

    func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }

    mutating func signageTimers() {
        guard let goal = state.goal else { return }
        let now = state.now
        let lastSign = state.marks.lastAnySignAt ?? -Double.infinity
        if !state.marks.scanPrompted, lastSign < state.marks.scanAnchor, now - state.marks.scanAnchor >= SessionTuning.scanPrompt {
            let line = state.progress.signMemory.map {
                SessionPhrases.remembered(aisleName(goal), number: $0.number, clock: relativeClock($0.bearing))
            } ?? SessionPhrases.noSigns
            if guide(line) { state.marks.scanPrompted = true }
        }
        // Sign out of view (overhead, or inside an aisle): step back and vote, once per goal.
        // Anchored on the last recalculate too, so time spent talking doesn't count.
        if !state.progress.voteDone, goal.category != nil, state.progress.signMemory == nil,
           now - max(lastSign, state.marks.scanAnchor) >= SessionTuning.outOfView {
            state.progress.voteDone = true
            announce(SessionPhrases.stepBackTwo)
            enter(.shelfVote)
            announce(SessionPhrases.faceLeft)
            return
        }
        lostTimers()
    }

    /// ~30 s with nothing related to the goal → "I've lost track…"; ~60 s more → guidance paused (§5.12).
    mutating func lostTimers() {
        let now = state.now
        if let lost = state.progress.lostTrackAt {
            if now - lost >= SessionTuning.lostPause { pauseLost() }
        } else if state.step == .findingSignage, now - state.progress.evidenceAt >= SessionTuning.lostTrack,
                  guide(SessionPhrases.lostTrack) {
            state.progress.lostTrackAt = now
        }
    }
}

// MARK: - Shelf vote, arrival, walking the aisle

extension ShoppingSession {
    mutating func voteTimers() {
        let elapsed = state.now - state.stepStartedAt
        if state.marks.voteStage == 0, elapsed >= SessionTuning.voteFace {
            state.marks.voteStage = 1
            announce(SessionPhrases.faceRight)
        } else if state.marks.voteStage == 1, elapsed >= 2 * SessionTuning.voteFace {
            announce(SessionPhrases.walkToEnd)
            enter(.findingSignage)
        }
    }

    mutating func aisleVerdict(_ aisle: String?, evidence: [String]) {
        guard let goal = state.goal else { return }
        let isTarget = aisle != nil && aisle == goal.category
        if isTarget { noteEvidence() }
        switch state.step {
        case .findingSignage, .shelfVote:
            if isTarget, let a = aisle { confirmAisleByVote(goal, aisle: a, evidence: evidence); return }
            if let t = state.progress.lastTargetSignAt, state.now - t < SessionTuning.signOverride { return }
            guard let target = goal.category else { return }          // word search: no aisle to compare
            let name = aisleName(goal)
            if let a = aisle {
                let adjacent = (catalog[target]?.adjacent ?? []).contains(a) || (catalog[a]?.adjacent ?? []).contains(target)
                let other = otherAisleWords(a, excluding: name, max: adjacent ? 2 : 1)
                guide(adjacent ? SessionPhrases.adjacent(other, target: name) : SessionPhrases.different(other, target: name), dedupe: true)
                if state.step == .shelfVote { enter(.findingSignage) }
            } else if state.step == .findingSignage, !state.marks.unsureSaid, guide(SessionPhrases.unsure) {
                state.marks.unsureSaid = true
            }
        case .walkingAisle:
            guard isTarget, state.marks.turnBearing == nil else { return }
            announce(SessionPhrases.turnToShelf)
            enterPointing(prompt: true)
        default:
            break
        }
    }

    /// Target verdict: "This is the coffee aisle. I see coffee and tea on both sides." / "This looks like produce: bananas ahead."
    mutating func confirmAisleByVote(_ goal: Goal, aisle: String, evidence: [String]) {
        let name = aisleName(goal)
        let things = Array(unique(evidence.map { $0.lowercased() }).prefix(3))
        let visual = Set((catalog[aisle]?.visualClasses ?? []).map { $0.lowercased() })
        if !things.isEmpty, things.allSatisfy(visual.contains) {
            announce(SessionPhrases.looksLike(name, things: state.verbosity == .brief ? [] : things))
        } else {
            announce(SessionPhrases.thisIsAisle(name))
            if !things.isEmpty { narrate(SessionPhrases.seeOnBothSides(things)) }
        }
        enter(.walkingAisle)
        state.marks.shelfCueAt = state.now + SessionTuning.shelfCue
    }

    func otherAisleWords(_ aisle: String, excluding: String, max: Int) -> String {
        let words = (catalog[aisle]?.aisleWords ?? []).filter { normalizeText($0) != normalizeText(excluding) }
        return words.isEmpty ? displayAisle(aisle) : SessionPhrases.list(Array(words.prefix(max)))
    }

    /// "Stop. Aisle 6 is at 9 o'clock." → "Turn to 9 o'clock." (speech only)
    mutating func arrivedAtAisle(clock: Int) {
        guard let goal = state.goal, state.step == .findingSignage || state.step == .shelfVote else { return }
        let memory = state.progress.signMemory
        announce(SessionPhrases.stopAtAisle(number: memory?.number, name: aisleName(goal), clock: clock,
                                            categories: state.verbosity == .detailed ? memory?.words ?? [] : []))
        announce(SessionPhrases.turnTo(clock))
        noteEvidence()
        enter(.walkingAisle)
        state.marks.turnBearing = state.yaw + SessionGeometry.degrees(forClock: clock)
        state.marks.turnDueAt = state.now + SessionTuning.turnFallback
    }

    /// Facing into the aisle: "This is the coffee aisle. Walk through slowly."
    mutating func turnedIntoAisle() {
        guard let goal = state.goal else { return }
        state.marks.turnBearing = nil
        state.marks.turnDueAt = nil
        markAisleEntry()
        announce(SessionPhrases.thisIsAisle(aisleName(goal)))
        narrate(SessionPhrases.walkSlowly)
    }

    mutating func aisleTimers() {
        if let due = state.marks.turnDueAt, state.now >= due { turnedIntoAisle() }
        if let cue = state.marks.shelfCueAt, state.now >= cue {
            state.marks.shelfCueAt = nil
            announce(SessionPhrases.turnToShelf)
            enterPointing(prompt: true)
        }
    }

    /// Walked the aisle both ways: turned back and walked as far again (pedometer).
    mutating func aisleWalked() {
        if let target = state.marks.turnBearing {
            if abs(SessionGeometry.angle(state.yaw, from: target)) <= SessionTuning.turnDoneDegrees { turnedIntoAisle() }
            return
        }
        guard let y0 = state.progress.entryYaw, let s0 = state.progress.entrySteps else { return }
        if let s1 = state.progress.turnBackSteps {
            if state.steps - s1 >= max(SessionTuning.minAisleSteps, s1 - s0) { notFound() }
        } else if abs(SessionGeometry.angle(state.yaw, from: y0)) >= SessionTuning.turnBackDegrees,
                  state.steps - s0 >= SessionTuning.minAisleSteps {
            state.progress.turnBackSteps = state.steps
        }
    }
}

// MARK: - Destinations

extension ShoppingSession {
    mutating func destinationSigns(_ signs: [AisleSign], _ d: Destination) {
        let words = (destinationWords[d] ?? []).map(normalizeText)
        let hit = signs.first { s in
            let text = s.words.map(normalizeText).joined(separator: " ")
            return words.contains { SessionText.has(text, $0) }
        }
        guard let sign = hit else {
            if !signs.isEmpty, state.now - (state.marks.lastOtherSignsAt ?? -Double.infinity) >= SessionTuning.otherSignsInterval,
               guide(SessionPhrases.notOnSigns(d == .checkout ? "checkout" : "customer service"), dedupe: true) {
                state.marks.lastOtherSignsAt = state.now
            }
            return
        }
        state.progress.lastDestinationSignAt = state.now
        noteEvidence()
        let line = d == .checkout ? SessionPhrases.checkoutsAhead(sign.clock) : SessionPhrases.serviceDesk(sign.clock)
        if !state.marks.destinationSeen {
            state.marks.destinationSeen = true
            announce(line)
            if d == .checkout { narrate(SessionPhrases.cashierHelp) }
            state.marks.lastDirectionAt = state.now
        } else if state.now - (state.marks.lastDirectionAt ?? -Double.infinity) >= SessionTuning.directionInterval,
                  guide(line, dedupe: true) {
            state.marks.lastDirectionAt = state.now
        }
    }

    mutating func destinationTimers() {
        let now = state.now
        let lastSign = state.marks.lastAnySignAt ?? -Double.infinity
        if !state.marks.scanPrompted, lastSign < state.marks.scanAnchor, now - state.marks.scanAnchor >= SessionTuning.scanPrompt,
           guide(SessionPhrases.noSigns) {
            state.marks.scanPrompted = true
        }
        let seen = max(state.progress.lastDestinationSignAt ?? -Double.infinity, state.stepStartedAt)
        if !state.marks.destinationNotFoundSaid, now - seen >= SessionTuning.destinationNotFound,
           guide(SessionPhrases.destinationNotFound) {
            state.marks.destinationNotFoundSaid = true
        }
    }
}

/// Angles in degrees, growing clockwise (to the right).
enum SessionGeometry {
    static func degrees(forClock clock: Int) -> Double { normalize(Double(clock % 12) * 30) }

    /// `a − b` in (−180, 180].
    static func angle(_ a: Double, from b: Double) -> Double { normalize(a - b) }

    static func normalize(_ a: Double) -> Double {
        var d = a.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }
}
