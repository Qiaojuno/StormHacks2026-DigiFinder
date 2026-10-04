// Entrance, signage, shelf vote, aisle arrival and destination signs (§5.2, §5.6, §5.7).

// MARK: - Inside / outside and the entrance (P1)

extension ShoppingSession {
    /// Outside detected (or said) → Entrance; "You're inside" → FindAisle (the place is a store from then on).
    mutating func setOutside(_ isOutside: Bool, saidByUser: Bool) {
        let changed = state.outside != isOutside
        state.outside = isOutside
        if isOutside {
            // Not in a general place (home, campus, outdoors…): there the cameras see "outside" without a store.
            guard changed || saidByUser, saidByUser || !isGeneral, !placeWaiting || saidByUser,
                  state.step == .idle || state.step == .findAisle else { return }
            if state.step == .idle && (state.askingNext || state.pendingChoice != nil || state.openingPending) { return }
            enterEntrance()
        } else if state.step == .entrance {
            announce(SessionPhrases.inside)
            state.place = .store                              // came in through a store entrance
            state.placeCheck = nil
            if hasActiveGoal { enterFindAisle() } else { enter(.idle) }
        }
    }

    mutating func enterEntrance() {
        enter(.entrance)
        let online = state.online && state.onlineHelp
        state.entrance = SessionEntranceState(online: online)
        announce(SessionPhrases.lookingForEntrance)
        if online { requestPick() }
    }

    mutating func requestPick() {
        out.append(.pickEntrance)
        state.entrance.tries += 1
        state.entrance.lastPickAt = state.now
        state.entrance.awaitingPick = true
        state.entrance.waitingForTurn = false
    }

    mutating func entrancePicked(_ pick: EntrancePick?) {
        guard state.step == .entrance, state.entrance.online else { return }
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
        // The runner fills the clocks from Stream B intrinsics; without them, a nominal field of view.
        let degrees = p.clock.map(clockDegrees)
            ?? Geometry.degreesRight(portraitX: p.x, horizontalFOV: SessionTuning.stillHorizontalFOV)
        state.entrance.bearing = state.yaw + degrees
        state.entrance.lastTrackedAt = state.now
        state.entrance.tries = 0
        guard !state.entrance.pickAnnounced else { return }       // say it once
        state.entrance.pickAnnounced = true
        announce(SessionPhrases.entranceAt(p.clock ?? clockPosition(degreesRight: degrees), kind: p.kind))
        if let c = p.cartCorralClock ?? p.cartCorralX.map({
            clockPosition(degreesRight: Geometry.degreesRight(portraitX: $0, horizontalFOV: SessionTuning.stillHorizontalFOV))
        }) {
            narrate(SessionPhrases.cartCorral(c))
        }
        if state.verbosity == .detailed, let note = p.note, !note.isEmpty { narrate(note) }
    }

    mutating func doorsSeen(_ doors: [DoorObservation]) {
        guard state.step == .entrance, !doors.isEmpty else { return }
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
            guide(SessionPhrases.exitDoor(otherClock: other.clock, distance: other.distance, steps: state.distanceInSteps), dedupe: true)
            return
        }
        if nearest.label == .unknown, !state.entrance.noSignSaid {     // no sign on any door: nearest, honestly
            state.entrance.noSignSaid = true
            announce(SessionPhrases.doorNoSign(clock: nearest.clock, distance: nearest.distance, steps: state.distanceInSteps))
        }
    }

    /// Once, within ~8 m: "Entrance ahead, about 7 meters, 12 o'clock."
    mutating func announceEntranceAhead(_ d: DoorObservation) {
        guard !state.entrance.aheadSaid, let m = d.distance, m <= SessionTuning.entranceAnnounceMeters else { return }
        state.entrance.aheadSaid = true
        announce(SessionPhrases.entranceAhead(m, clock: d.clock, steps: state.distanceInSteps))
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
        guard state.pause == nil else { return }
        if canObserve, !signs.isEmpty { state.marks.lastAnySignAt = state.now }   // any sign resets the "no sign" wait
        guard state.goal == nil || !isGeneral else { return }                  // not a store: no sign prompts
        let navigating = state.step == .findAisle && state.goal != nil

        // While the user talks, a target sign is still remembered (its bearing), just not spoken.
        if let goal = state.goal, navigating, let hit = targetSign(in: signs, words: navigationWords(goal), goal: goal) {
            rememberTargetSign(hit.sign)
            guard canObserve else { return }
            if state.vote != nil { state.vote = nil }          // a readable target sign ends the vote
            signDirection(hit.sign, word: hit.word)
            return
        }
        guard canObserve else { return }
        switch state.step {
        case .inAisle:
            guard let goal = state.goal, state.pendingPick == nil,
                  let hit = targetSign(in: signs.filter { $0.number == nil }, words: shelfWords(goal), goal: goal) else { return }
            noteEvidence()
            stopAtShelf(SessionPhrases.stopHereShelf(clock: hit.sign.clock))
        case .findAisle:
            if let d = state.destination { destinationSigns(signs, d) }
            else if let goal = state.goal, !signs.isEmpty, state.vote == nil { otherSigns(signs, goal: goal) }
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

    /// FindAisle in a store, looking for signs.
    mutating func signageTimers() {
        guard let goal = state.goal else { return }
        if state.vote != nil { voteProgress(); lostTimers(); return }
        let now = state.now
        let lastSign = state.marks.lastAnySignAt ?? -Double.infinity
        if !state.marks.scanPrompted, lastSign < state.marks.scanAnchor, now - state.marks.scanAnchor >= SessionTuning.scanPrompt {
            let line = state.progress.signMemory.map {
                SessionPhrases.remembered(aisleName(goal), number: $0.number, clock: relativeClock($0.bearing))
            } ?? SessionPhrases.noSigns
            if guide(line) { state.marks.scanPrompted = true }
        }
        // No readable sign for ~10 s (overhead, or inside an aisle): step back and vote, once per goal.
        // Any sign resets the wait; anchored on the last recalculate too, so time spent talking doesn't count.
        if !state.progress.voteDone, goal.category != nil, state.progress.signMemory == nil, state.aisleBearing == nil,
           now - max(lastSign, state.marks.scanAnchor) >= SessionTuning.outOfView {
            startVote()
            return
        }
        lostTimers()
    }

    /// ~30 s with nothing related to the goal → "I've lost track…"; ~60 s more → guidance paused (§5.12).
    mutating func lostTimers() {
        let now = state.now
        if let lost = state.progress.lostTrackAt {
            if now - lost >= SessionTuning.lostPause { pauseLost() }
        } else if state.vote == nil, now - state.progress.evidenceAt >= SessionTuning.lostTrack,
                  guide(SessionPhrases.lostTrack) {
            state.progress.lostTrackAt = now
        }
    }
}

// MARK: - Shelf vote (sub-state of FindAisle, §5.7)

extension ShoppingSession {
    mutating func startVote() {
        state.progress.voteDone = true
        state.vote = SessionVote(since: state.now, baseYaw: state.yaw, stepsAtPrompt: state.steps)
        announce(SessionPhrases.stepBackTwo)
    }

    /// Step back (then Standing) → face 9 o'clock → face 3 o'clock → back to the sign search.
    mutating func voteProgress() {
        guard var v = state.vote, !guidanceHeld else { return }
        let now = state.now
        switch v.stage {
        case .stepBack:
            if state.isWalking || state.steps > v.stepsAtPrompt { v.moved = true }
            // Once Standing after stepping back (without motion data: at once).
            guard (v.moved || !state.hasMotion) && !state.isWalking else { state.vote = v; return }
            v.stage = .left
            v.since = now
            v.facingSince = state.hasMotion ? nil : now
            state.vote = v
            announce(SessionPhrases.faceLeft)
        case .left, .right:
            let side = v.baseYaw + (v.stage == .left ? -90 : 90)
            let facing = !state.hasMotion || abs(SessionGeometry.angle(state.yaw, from: side)) <= SessionTuning.voteFacingDegrees
            if facing { v.facingSince = v.facingSince ?? now } else { v.facingSince = nil }
            let checked = (v.facingSince.map { now - $0 >= SessionTuning.voteFace } ?? false)
                || now - v.since >= 2 * SessionTuning.voteFace
            guard checked else { state.vote = v; return }
            if v.stage == .left {
                v.stage = .right
                v.since = now
                v.facingSince = state.hasMotion ? nil : now
                state.vote = v
                announce(SessionPhrases.faceRight)
            } else {
                state.vote = nil                                  // both sides checked: back to the signs
                state.marks.scanAnchor = now
                state.marks.scanPrompted = true
                announce(SessionPhrases.walkToEnd)
            }
        }
    }
}

// MARK: - Aisle verdict, arrival, walking the aisle

extension ShoppingSession {
    mutating func aisleVerdict(_ aisle: String?, evidence: [String]) {
        guard let goal = state.goal, !isGeneral else { return }
        let isTarget = aisle != nil && aisle == goal.category
        if isTarget { noteEvidence() }
        switch state.step {
        case .findAisle:
            if isTarget, let a = aisle { confirmAisleByVote(goal, aisle: a, evidence: evidence); return }
            if let t = state.progress.lastTargetSignAt, state.now - t < SessionTuning.signOverride { return }
            guard let target = goal.category else { return }          // word search: no aisle to compare
            let name = aisleName(goal)
            if let a = aisle {
                let adjacent = (catalog[target]?.adjacent ?? []).contains(a) || (catalog[a]?.adjacent ?? []).contains(target)
                let other = otherAisleWords(a, excluding: name, max: adjacent ? 2 : 1)
                guide(adjacent ? SessionPhrases.adjacent(other, target: name) : SessionPhrases.different(other, target: name), dedupe: true)
                state.vote = nil
            } else if state.vote == nil, !state.marks.unsureSaid, guide(SessionPhrases.unsure) {
                state.marks.unsureSaid = true
            }
        case .inAisle:
            // The vote located the item's section.
            guard isTarget, state.pendingPick == nil else { return }
            stopAtShelf(SessionPhrases.stopHere)
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
        enter(.inAisle)
        markAisleEntry()
        narrate(SessionPhrases.walkSlowly)
    }

    func otherAisleWords(_ aisle: String, excluding: String, max: Int) -> String {
        let words = (catalog[aisle]?.aisleWords ?? []).filter { normalizeText($0) != normalizeText(excluding) }
        return words.isEmpty ? displayAisle(aisle) : SessionPhrases.list(Array(words.prefix(max)))
    }

    /// The target sign was passed (dead reckoning): "Stop. Aisle 6 is at 9 o'clock." The phase stays FindAisle until
    /// the vote confirms the aisle or the user walks into it (heading within ~45° of its bearing).
    mutating func arrivedAtAisle(clock: Int) {
        guard let goal = state.goal, state.step == .findAisle, !isGeneral else { return }
        let memory = state.progress.signMemory
        announce(SessionPhrases.stopAtAisle(number: memory?.number, name: aisleName(goal), clock: clock,
                                            categories: state.verbosity == .detailed ? memory?.words ?? [] : []))
        noteEvidence()
        state.vote = nil
        state.aisleBearing = state.yaw + SessionGeometry.degrees(forClock: clock)
    }

    /// Walking into the aisle: "This is the coffee aisle. Walk through slowly."
    mutating func walkedIntoAisle() {
        guard let goal = state.goal else { return }
        enter(.inAisle)
        markAisleEntry()
        announce(SessionPhrases.thisIsAisle(aisleName(goal)))
        narrate(SessionPhrases.walkSlowly)
    }

    /// "Stop here. Turn to the shelf…" then Pick once the user stands.
    mutating func stopAtShelf(_ line: String) {
        announce(line)
        state.pendingPick = .shelf
        state.pickReturn = .inAisle
        pickWhenStanding()
    }

    /// LiDAR: the shelves stopped on both sides.
    mutating func aisleEndSeen() {
        guard state.step == .inAisle, let s0 = state.progress.entrySteps,
              state.steps - s0 >= SessionTuning.minAisleSteps else { return }
        aisleEnd()
    }

    /// Pedometer backup: ~20 m since entering the aisle.
    mutating func aisleEndBackup() {
        guard state.step == .inAisle, let s0 = state.progress.entrySteps else { return }
        if Float(state.steps - s0) * SessionTuning.stepLengthMeters >= SessionTuning.aisleEndBackupMeters { aisleEnd() }
    }

    /// "End of aisle. Item not found here." + what the user can do; once per goal.
    mutating func aisleEnd() {
        guard state.goal != nil, !state.progress.aisleEndSaid, state.pendingPick == nil else { return }
        state.progress.aisleEndSaid = true
        announce(SessionPhrases.aisleEnd)
        announce(SessionPhrases.aisleEndOffer)
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
        let line = d == .checkout ? SessionPhrases.checkoutsAhead(sign.clock, distance: sign.distance, steps: state.distanceInSteps)
                                   : SessionPhrases.serviceDesk(sign.clock, distance: sign.distance, steps: state.distanceInSteps)
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

// MARK: - Grocery or not (Gemini at app open; manual settings win)

extension ShoppingSession {
    /// Not a store: look around for the item itself (no signs, vote or aisle end). Destinations always use signs.
    /// General is the default (owner decision): the store flow runs only when Gemini said "grocery store" with enough
    /// confidence, the user came in through a store entrance, or the user chose store mode.
    var isGeneral: Bool {
        if !state.onDeviceItemSearch { return true }       // no sign reading: always the Gemini-guided search
        if let o = state.placeOverride { return o == .general }
        return state.place != .store
    }

    /// Waiting for the grocery answer: FindAisle stays quiet (signs and sightings are still handled).
    var placeWaiting: Bool { state.placeOverride == nil && state.placeCheck != nil }

    mutating func requestPlaceCheck() {
        state.placeTries += 1
        state.placeCheck = SessionPlaceCheck(askedAt: state.now, tries: state.placeTries)
        out.append(.classifyPlace)
    }

    mutating func placeClassified(_ answer: PlaceAnswer?) {
        guard state.placeCheck != nil else { return }                                  // late answers are dropped
        if let a = answer {
            state.placeConfidence = a.confidence
            state.placeScene = a.scene
            if a.confidence >= SessionTuning.placeMinConfidence {
                placeDecided(a.grocery ? .store : .general,
                             line: a.grocery ? SessionPhrases.inGroceryStore : SessionPhrases.looksLikePlace(a.scene))
                return
            }
            if state.placeTries < 2 { requestPlaceCheck(); return }                    // unsure: 3 new photos, once
        }
        placeDecided(.general, line: SessionPhrases.couldntTellPlace)                  // no answer: general
    }

    mutating func placeTimers() {
        guard let check = state.placeCheck, state.now - check.askedAt >= SessionTuning.placeTimeout else { return }
        placeDecided(.general, line: SessionPhrases.couldntTellPlace)
    }

    /// Said once, right before the opening question.
    mutating func placeDecided(_ place: SessionPlace?, line: String) {
        state.placeCheck = nil
        state.place = place
        state.placeDecidedAt = state.now
        // Owner decision: the place is never announced. A request that got "Loading." now gets its real line.
        state.openingPending = false
        if state.loadingGoal {
            state.loadingGoal = false
            if let g = state.goal { announce(SessionPhrases.nowLookingFor(name(g))) }
        }
        placeChanged()
    }

    /// "It's nearby" / Settings nearby mode (general), "store mode" (store), or automatic (nil).
    mutating func setPlaceOverride(_ p: SessionPlace?) {
        guard state.placeOverride != p else { return }
        state.placeOverride = p
        if p != nil {                                           // a manual setting skips the Gemini check
            state.placeCheck = nil
            if state.openingPending {                           // and its announcement
                state.openingPending = false
                if !hasActiveGoal && !state.askingNext { announce(SessionPhrases.askGoal) }
            }
        }
        state.placeDecidedAt = state.now
        placeChanged()
    }

    /// The search adapts to the place (silent unless the user must act).
    mutating func placeChanged() {
        guard state.goal != nil else { return }
        if isGeneral {
            switch state.step {
            case .inAisle, .entrance: enterFindAisle()
            case .findAisle:
                state.vote = nil
                state.aisleBearing = nil
                state.marks = SessionStepMarks(anchor: state.now)
                guide(SessionPhrases.turnSlowly)
            default: break
            }
        } else if state.step == .findAisle {
            state.marks.scanAnchor = state.now                 // sign prompts start now
            state.marks.scanPrompted = false
        }
    }

    /// Gemini-guided search. Owner decisions: in a grocery store it never gives up (elsewhere ~60 s with no sighting →
    /// "I couldn't find X."). Every ~15 s without a sighting: "Stop and look around. I need context."; once the user
    /// has stood still ~4 s (two Gemini scans): "Keep going." A sighting answers it instead.
    mutating func nearbyTimers() {
        let now = state.now
        let anchor = max(state.stepStartedAt, state.itemSeenAt ?? -Double.infinity, state.placeDecidedAt ?? -Double.infinity)
        let inStore = (state.placeOverride ?? state.place) == .store
        if !inStore, now - anchor >= SessionTuning.nearbyGiveUp, let g = state.goal {
            state.marks.contextAskedAt = nil
            announce(SessionPhrases.notFoundNearby(name(g)))
            out.append(.chime(.done))
            advanceToNext()
            return
        }
        if let asked = state.marks.contextAskedAt {
            if state.isWalking {
                state.marks.contextStillSince = nil
                guard now - asked >= SessionTuning.contextReask else { return }
                if guide(SessionPhrases.needContext) { state.marks.contextAskedAt = now }
                return
            }
            let still = state.marks.contextStillSince ?? now
            state.marks.contextStillSince = still
            guard now - still >= SessionTuning.contextStill else { return }
            if guide(SessionPhrases.keepGoing) {
                state.marks.contextAskedAt = nil
                state.marks.contextStillSince = nil
                state.marks.lastPointCueAt = now
            }
            return
        }
        let last = max(state.marks.lastPointCueAt ?? -Double.infinity, anchor)
        if now - last >= SessionTuning.nearbyPrompt, guide(SessionPhrases.needContext) {
            state.marks.lastPointCueAt = now
            state.marks.contextAskedAt = now
            state.marks.contextStillSince = nil
        }
    }
}

// MARK: - Item in view: the global rule in every search phase (Entrance, FindAisle, InAisle)

extension ShoppingSession {
    mutating func itemSeen(clock: Int, distance: Float?) {
        guard let g = state.goal, [.entrance, .findAisle, .inAisle].contains(state.step) else { return }
        noteEvidence()
        state.itemSeenAt = state.now
        state.marks.contextAskedAt = nil                    // the sighting is the context: no "Keep going."
        state.marks.contextStillSince = nil
        let ahead = clock == 12 || clock == 11 || clock == 1
        if ahead, let d = distance, d <= SessionTuning.reachMeters {
            state.itemClock = clock
            state.itemDistance = distance
            if state.isWalking {
                // "Stop. Coffee at 12 o'clock." once; Pick when the user stands.
                guard state.pendingPick != .item else { return }
                state.pendingPick = .item
                state.pickReturn = state.step == .entrance ? .findAisle : state.step
                announce(SessionPhrases.stopItem(name(g), clock: clock))
                return
            }
            state.pickReturn = state.step == .entrance ? .findAisle : state.step
            reachItem(g)
            return
        }
        guard state.pendingPick == nil else { return }
        let changed = clock != state.itemClock
        let due = state.now - (state.marks.lastDirectionAt ?? -Double.infinity) >= SessionTuning.itemInterval
        state.itemClock = clock
        state.itemDistance = distance
        guard changed || due else { return }
        if guide(SessionPhrases.itemAt(name(g), clock: clock, distance: distance, steps: state.distanceInSteps), dedupe: true,
                 repeatAfter: SessionTuning.itemInterval) {
            state.marks.lastDirectionAt = state.now
        }
    }

    /// Gemini item finder: the item isn't in view; where to look. Search phases only, new text only, ≤ 1 per ~8 s,
    /// never while a "Stop." waits for Standing or just after a sighting.
    mutating func searchHint(_ hint: String) {
        guard state.goal != nil, [.entrance, .findAisle, .inAisle].contains(state.step), state.pendingPick == nil else { return }
        let line = SessionPhrases.searchHint(hint)
        guard !line.isEmpty else { return }
        if let seen = state.itemSeenAt, state.now - seen < SessionTuning.searchHintAfterSighting { return }
        let key = normalizeText(line)
        if let last = state.progress.lastSearchHint, last == key { return }
        if let at = state.progress.lastSearchHintAt, state.now - at < SessionTuning.searchHintInterval { return }
        guard guide(line) else { return }
        state.progress.lastSearchHint = key
        state.progress.lastSearchHintAt = state.now
    }

    /// Within reach and Standing: Pick ("Point at it with one finger."), or found for a household object.
    mutating func reachItem(_ g: Goal) {
        // Owner decision: within reach is not the end. Ask the user to pick it up and hold it out; Gemini checks the
        // held item (`.confirmed`): right → done, wrong → "Put it back." and the search resumes.
        if !state.onDeviceItemSearch {
            enter(.confirm)
            state.marks.holdPromptAt = state.now
            announce(SessionPhrases.withinReach(name(g)))
            announce(SessionPhrases.pickUpHold)
            return
        }
        if g.category == nil && g.visualClass != nil {
            // Household object (no label to read): within reach ahead is found.
            announce(SessionPhrases.withinReach(name(g)))
            out.append(.chime(.done))
            out.append(.markDone(g))
            state.foundCount += 1
            advanceToNext()
            return
        }
        enter(.pick)
        announce(SessionPhrases.pointAtIt)
    }

    /// Motion layer → phases (level-triggered, so a change during Ask or a danger alert is picked up after it).
    mutating func pickWhenStanding() {
        guard let reason = state.pendingPick, !state.isWalking, !guidanceHeld else { return }
        state.pendingPick = nil
        switch reason {
        case .item:
            guard let g = state.goal, let seen = state.itemSeenAt, state.now - seen <= SessionTuning.itemMemory else { return }
            reachItem(g)
        case .shelf:
            enter(.pick)
            announce(SessionPhrases.pointAtShelf)
        }
    }

    /// The user walked on: forget a stale "Stop." so it can be said again.
    mutating func expireItemStop() {
        guard state.pendingPick == .item else { return }
        if state.now - (state.itemSeenAt ?? -Double.infinity) > SessionTuning.itemMemory { state.pendingPick = nil }
    }
}
