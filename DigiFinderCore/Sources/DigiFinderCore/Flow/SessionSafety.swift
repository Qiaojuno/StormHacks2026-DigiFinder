// Danger cut-in, stairs, positioning prompts, motion, system events and timers (§5.3, §5.4, §5.8, §5.16).

// MARK: - Danger (§5.3). The safety lane already vibrated, stopped speech and spoke the alert.
// Alerts depend on the motion state only; nothing here (or anywhere in the session) gates them by phase or overlay.

extension ShoppingSession {
    mutating func danger(cutRecording: Bool) {
        state.dangerSince = state.now
        guard cutRecording else { return }
        state.isListening = false
        reply(SessionPhrases.sayAgain, prompt: false)        // the user presses volume up to answer
    }

    /// After an alert, the way straight ahead opened up: "Clear ahead, about 4 meters. Walk straight." (§5.3)
    mutating func pathClear(meters: Float?) {
        reply(clearPathPhrase(meters: meters, inSteps: state.distanceInSteps), prompt: false)
    }

    /// Path clear → recalculate the current step and speak a fresh prompt, then the Gemini lines that waited.
    mutating func dangerCleared() {
        state.dangerSince = nil
        recalculate()
        switch state.step {
        case .pick: guide(SessionPhrases.pointAtShelf)
        case .confirm: guide(SessionPhrases.holdUp)
        default: break                                       // the next frames speak (de-dupe cleared)
        }
        releaseAfterDanger()
    }

    /// Owner decision: Gemini answers and hints wait for the alert to end instead of being dropped.
    mutating func holdAfterDanger(_ e: SessionEvent) {
        if case .searchHint = e { state.afterDanger.removeAll { if case .searchHint = $0 { return true }; return false } }
        if e == .crowded, state.afterDanger.contains(.crowded) { return }
        state.afterDanger.append(e)
    }

    mutating func releaseAfterDanger() {
        let waiting = state.afterDanger
        state.afterDanger = []
        for e in waiting {
            switch e {
            case .searchHint(let text): if canObserve { searchHint(text) }
            case .assistAnswer(let say, let find): assistAnswer(say: say, find: find)
            case .crowded: crowdWarning()
            default: break
            }
        }
    }
}

// MARK: - Stairs (§5.4): spoken only, once per staircase, never shortened.

extension ShoppingSession {
    mutating func stairs(_ o: StairsObservation) {
        if var m = state.stairs, m.up == o.up, state.now - m.lastSeenAt < SessionTuning.stairsForget {
            m.distance = o.distance
            m.stepsAtObservation = state.steps
            m.lastSeenAt = state.now
            let near = !m.nearSaid && o.distance <= SessionTuning.stairsNearMeters
            if near { m.nearSaid = true }
            state.stairs = m
            if near { sayStairs(SessionPhrases.stairsNear) }
            return
        }
        state.stairs = SessionStairsMemory(up: o.up, distance: o.distance, stepsAtObservation: state.steps,
                                           lastSeenAt: state.now, nearSaid: o.distance <= SessionTuning.stairsNearMeters)
        sayStairs(SessionPhrases.stairs(o, steps: state.distanceInSteps))
    }

    /// The floor near the feet isn't visible from the lanyard: count down with the pedometer.
    mutating func stairsCountdown() {
        guard var m = state.stairs, !m.nearSaid else { return }
        let walked = Float(max(0, state.steps - m.stepsAtObservation)) * SessionTuning.stepLengthMeters
        guard m.distance - walked <= SessionTuning.stairsNearMeters else { return }
        m.nearSaid = true
        state.stairs = m
        sayStairs(SessionPhrases.stairsNear)
    }

    /// Never record while speaking: a stairs line cuts the recording like a danger alert.
    mutating func sayStairs(_ text: String) {
        let cut = state.isListening
        if cut {
            out.append(.cancelListening)
            state.isListening = false
        }
        speak(text, .stairs, prompt: false)
        if cut { reply(SessionPhrases.sayAgain, prompt: false) }
    }
}

// MARK: - Wet floor sign (owner decision): on-device text reader, walking only, one vibration.

/// Words that mean a wet floor sign (English / French, as the text reader is set up).
public func isWetFloorSignText(_ lines: [String]) -> Bool {
    let t = lines.joined(separator: " ").lowercased()
    return ["wet floor", "caution", "piso mojado", "sol glissant", "plancher mouill"].contains { t.contains($0) }
        || (t.contains("wet") && t.contains("floor"))
}

extension ShoppingSession {
    static let wetFloorCooldown = 20.0
    /// "Lot of people around you" at most this often (s).
    static let crowdWarningInterval = 60.0

    /// Spoken as a reply so it waits for an alert instead of being dropped (owner decision).
    mutating func crowdWarning() {
        guard state.streaming else { return }
        if let at = state.crowdWarnedAt, state.now >= at, state.now - at < Self.crowdWarningInterval { return }
        state.crowdWarnedAt = state.now
        reply(SessionPhrases.crowded, prompt: false)
    }

    mutating func wetFloorSign(clock: Int) {
        guard state.streaming, state.isWalking else { return }
        if let at = state.wetFloorSignAt, state.now >= at, state.now - at < Self.wetFloorCooldown { return }
        state.wetFloorSignAt = state.now
        out.append(.buzz)
        sayStairs(SessionPhrases.wetFloorSign(clock: clock))      // safety line: not cut, not stale
    }
}

// MARK: - Positioning (§5.8) and motion

extension ShoppingSession {
    mutating func positioning(_ hint: PositioningHint) {
        let interval: Double
        let step = state.step
        switch hint {
        case .phoneFlipped:                                  // walking only (Safety checks it only then); max once per 30 s
            guard state.isWalking, step != .idle else { return }
            interval = SessionTuning.flippedInterval
        case .tiltUp, .tiltDown:                             // never: the phone hangs on a lanyard (owner decision)
            return
        case .slowDown:                                      // only matters while walking, or while pointing / holding up
            guard state.isWalking || step == .pick || step == .confirm else { return }
            interval = SessionTuning.hintInterval
        case .stepBack, .moveCloser:                         // reading labels at the shelf only
            guard state.vote != nil || step == .pick || step == .confirm else { return }
            interval = SessionTuning.hintInterval
        case .pointInFront:
            guard step == .pick else { return }
            interval = SessionTuning.hintInterval
        default:
            guard step != .idle else { return }
            interval = hint == .tooDark ? SessionTuning.darkInterval : SessionTuning.hintInterval
        }
        let key = "\(hint)"
        if let last = state.speech.hintTimes[key], state.now - last < interval { return }
        if guide(SessionPhrases.positioning(hint)) { state.speech.hintTimes[key] = state.now }
    }

    /// Layer 1 → layer 2: the phases read the motion state here; they never set it.
    mutating func motion(yaw: Double, steps: Int, walking: Bool) {
        state.yaw = yaw
        state.steps = steps
        state.isWalking = walking
        state.hasMotion = true
        stairsCountdown()
        guard !guidanceHeld else { return }
        switch state.step {
        case .entrance:
            pickWhenStanding()
            if state.step == .entrance { entranceTurned() }
        case .findAisle:
            pickWhenStanding()
            guard state.step == .findAisle else { return }
            if let b = state.aisleBearing, walking,
               abs(SessionGeometry.angle(yaw, from: b)) <= SessionTuning.aisleHeadingDegrees {
                walkedIntoAisle()                             // heading into the remembered aisle
            } else if state.vote != nil {
                voteProgress()
            }
        case .inAisle:
            pickWhenStanding()
            if state.step == .inAisle { aisleEndBackup() }
        case .pick:
            if walking { enter(state.pickReturn) }            // moved on: back where Pick came from, silently
        case .idle, .confirm:
            break
        }
    }
}

// MARK: - System events (§5.16)

extension ShoppingSession {
    mutating func system(_ s: SystemEvent) {
        switch s {
        case .backgrounded: backgrounded()
        case .foregrounded: foregrounded()
        case .batteryLow: break                              // not announced (owner decision)
        case .thermal(let level): thermal(level)
        case .audioRouteChanged: speak(state.lastPrompt, .guidance, prompt: false)   // continue on the speaker
        case .cameraDenied: notice("camera", SessionPhrases.cameraOff)
        case .micDenied: notice("mic", SessionPhrases.micOff)
        case .online(let on): online(on)
        }
    }

    mutating func notice(_ key: String, _ text: String) {
        guard state.speech.notices.insert(key).inserted else { return }
        speak(text, .guidance, prompt: false)
    }

    /// Screen lock, call, Siri: "Guidance paused, camera off."
    mutating func backgrounded() {
        guard state.step != .idle || state.askPending, state.pause != .background else { return }
        if state.isListening {
            out.append(.cancelListening)
            state.isListening = false
        }
        if state.askPending {
            state.assist = nil
            state.askPending = false
        }
        state.pause = .background                            // overlay: the phase is kept
        state.held = []                                      // stale by the time the camera is back
        announce(SessionPhrases.pausedCameraOff)
        emitWork()
    }

    mutating func foregrounded() {
        guard state.pause == .background else { return }
        state.pause = nil
        emitWork()
        announce(SessionPhrases.back)
        recalculate()
    }

    mutating func thermal(_ level: ThermalLevel) {
        let old = state.thermal
        state.thermal = level
        // Heat is handled silently (owner decision): rates drop, and at critical only danger and stairs run.
        if old == .critical && level != .critical { recalculate() } else { emitWork() }
    }

    mutating func online(_ on: Bool) {
        state.online = on
        guard state.step == .entrance else { return }
        if !on {
            state.entrance.online = false
        } else if state.onlineHelp, !state.entrance.online, state.entrance.tries < SessionTuning.maxPicks {
            state.entrance.online = true
            state.entrance.waitingForTurn = false
        }
    }
}

// MARK: - Time (`.tick` only)

extension ShoppingSession {
    mutating func tick(_ t: Double) {
        if let last = state.lastTick, t > last { state.now += min(t - last, SessionTuning.maxTickGap) }
        state.lastTick = t
        checkTimers()
    }

    mutating func checkTimers() {
        let now = state.now
        // Safety net: a recording the runner never answered must not block volume up forever.
        if state.isListening, let started = state.listenStartedAt, now - started >= SessionTuning.stuckRecording {
            out.append(.cancelListening)
            recordingEnded()
            afterRecording()
        }
        if let since = state.dangerSince, now - since >= SessionTuning.dangerHold {
            state.dangerSince = nil
            recalculate()
            releaseAfterDanger()
        }
        let answerWaiting = state.afterDanger.contains { if case .assistAnswer = $0 { return true }; return false }
        if let a = state.assist, !answerWaiting, now - a.startedAt >= SessionTuning.assistTimeout {
            state.assist = nil                                   // no answer: the offline path, silently
            resumeAfterAsking(then: a)
        }
        if let s = state.surroundingsSince, now - s >= SessionTuning.surroundingsTimeout { state.surroundingsSince = nil }
        if let st = state.stairs, now - st.lastSeenAt >= SessionTuning.stairsForget { state.stairs = nil }
        guard !state.isListening else { return }
        if let lookup = state.lookup, now - lookup.startedAt >= SessionTuning.lookupTimeout { productLookedUp(nil) }
        if let pending = state.pendingChoice, let at = state.choiceAskedAt, now - at >= SessionTuning.answerTimeout {
            clearChoice()
            enqueue(pending, line: SessionPhrases.willAdd(name(pending)))
            recalculate()
        }
        placeTimers()
        if state.askingNext, state.step == .idle, let at = state.askingNextAt, now - at >= SessionTuning.answerTimeout {
            finishShopping()
        }
        guard !guidanceHeld else { return }
        switch state.step {
        case .entrance:
            entranceTimers()
            expireItemStop()
        case .findAisle:
            expireItemStop()
            if state.destination != nil { destinationTimers() }
            else if isGeneral { nearbyTimers() }
            else if !placeWaiting { signageTimers() }        // quiet while the grocery answer is pending
            else if state.vote != nil { voteProgress() }
        case .inAisle: expireItemStop()                      // no timer moves the user to the shelf
        case .pick: notFoundTimer()
        case .confirm:
            unclearTimers()
            notFoundTimer()
        case .idle: break
        }
    }
}
