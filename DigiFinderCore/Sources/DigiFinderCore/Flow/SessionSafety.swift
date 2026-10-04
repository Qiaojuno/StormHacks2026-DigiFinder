// Danger cut-in, stairs, positioning prompts, motion, system events and timers (§5.3, §5.4, §5.8, §5.16).

// MARK: - Danger (§5.3). The safety lane already vibrated, stopped speech and spoke the alert.

extension ShoppingSession {
    mutating func danger(cutRecording: Bool) {
        state.dangerSince = state.now
        guard cutRecording else { return }
        state.isListening = false
        state.listenDeadline = nil
        reply(SessionPhrases.sayAgain, prompt: false)
        listen(SessionTuning.autoListenSeconds)
    }

    /// Path clear → recalculate the current step and speak a fresh prompt.
    mutating func dangerCleared() {
        state.dangerSince = nil
        recalculate()
        switch state.step {
        case .pointing: guide(SessionPhrases.pointAtShelf)
        case .holdUpToCheck: guide(SessionPhrases.holdUp)
        default: break                                       // the next frames speak (de-dupe cleared)
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
        sayStairs(SessionPhrases.stairs(o))
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
            state.listenDeadline = nil
        }
        speak(text, .stairs, prompt: false)
        if cut {
            reply(SessionPhrases.sayAgain, prompt: false)
            listen(SessionTuning.autoListenSeconds)
        }
    }
}

// MARK: - Positioning (§5.8) and motion

extension ShoppingSession {
    mutating func positioning(_ hint: PositioningHint) {
        let interval: Double
        switch hint {
        case .phoneFlipped:                                  // not at the shelf; max once per 30 s
            guard state.step != .idle, state.step != .sessionDone, !(state.work?.shelfMode ?? false) else { return }
            interval = SessionTuning.flippedInterval
        case .pointInFront:
            guard state.step == .pointing else { return }
            interval = SessionTuning.hintInterval
        default:
            let camera: [Step] = [.findingEntrance, .findingSignage, .walkingAisle, .shelfVote, .pointing, .holdUpToCheck, .findingDestination]
            guard camera.contains(state.step) else { return }
            interval = hint == .tooDark ? SessionTuning.darkInterval : SessionTuning.hintInterval
        }
        let key = "\(hint)"
        if let last = state.speech.hintTimes[key], state.now - last < interval { return }
        if guide(SessionPhrases.positioning(hint)) { state.speech.hintTimes[key] = state.now }
    }

    mutating func motion(yaw: Double, steps: Int, walking: Bool) {
        state.yaw = yaw
        state.steps = steps
        state.isWalking = walking
        state.hasMotion = true
        stairsCountdown()
        guard !guidanceHeld else { return }
        switch state.step {
        case .findingEntrance: entranceTurned()
        case .walkingAisle: aisleWalked()
        default: break
        }
    }
}

// MARK: - System events (§5.16)

extension ShoppingSession {
    mutating func system(_ s: SystemEvent) {
        switch s {
        case .backgrounded: backgrounded()
        case .foregrounded: foregrounded()
        case .batteryLow(let percent): notice("battery-\(percent)", SessionPhrases.battery(percent))
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
        guard state.step != .idle, state.step != .sessionDone, state.pauseReason != .background else { return }
        if state.isListening {
            out.append(.cancelListening)
            state.isListening = false
            state.listenDeadline = nil
        }
        if state.step == .asking {
            state.askStartedAt = nil
            state.step = state.resumeStep ?? .idle
        }
        if state.step != .paused { state.resumeStep = state.step }
        state.step = .paused
        state.pauseReason = .background
        state.held = []                                      // stale by the time the camera is back
        announce(SessionPhrases.pausedCameraOff)
        emitWork()
    }

    mutating func foregrounded() {
        guard state.step == .paused, state.pauseReason == .background else { return }
        resumePausedStep()
        announce(SessionPhrases.back)
        recalculate()
    }

    mutating func thermal(_ level: ThermalLevel) {
        let old = state.thermal
        state.thermal = level
        if level == .serious && old != .serious && old != .critical { announce(SessionPhrases.hot) }
        if level == .critical && old != .critical { announce(SessionPhrases.tooHot) }
        if old == .critical && level != .critical { recalculate() } else { emitWork() }
    }

    mutating func online(_ on: Bool) {
        state.online = on
        guard state.step == .findingEntrance else { return }
        if !on {
            state.entrance.online = false
        } else if !state.entrance.online, state.entrance.tries < SessionTuning.maxPicks {
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
        if state.isListening, let deadline = state.listenDeadline, now >= deadline {   // the runner never answered
            state.isListening = false
            state.listenDeadline = nil
            afterRecording()
        }
        if let since = state.dangerSince, now - since >= SessionTuning.dangerHold {
            state.dangerSince = nil
            recalculate()
        }
        if state.step == .asking, let at = state.askStartedAt, now - at >= SessionTuning.askTimeout {
            state.askStartedAt = nil
            reply(SessionPhrases.noAnswer, prompt: false)
            resumeAfterAsking()
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
        if state.askingNext, state.step == .askingGoal, let at = state.askingNextAt, now - at >= SessionTuning.answerTimeout {
            finishShopping()
        }
        guard !guidanceHeld else { return }
        switch state.step {
        case .findingEntrance: entranceTimers()
        case .findingSignage: signageTimers()
        case .shelfVote:
            voteTimers()
            if state.step == .shelfVote { lostTimers() }
        case .walkingAisle:
            aisleTimers()
            if state.step == .walkingAisle { notFoundTimer() }
        case .pointing: notFoundTimer()
        case .holdUpToCheck:
            unclearTimers()
            notFoundTimer()
        case .findingDestination: destinationTimers()
        case .idle, .askingGoal, .asking, .sessionDone, .paused: break
        }
    }
}
