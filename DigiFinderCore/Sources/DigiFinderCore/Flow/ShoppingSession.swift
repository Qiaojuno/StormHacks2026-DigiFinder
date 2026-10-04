// Shopping flow state machine (§5): (state, event) -> (state, [Effect]). Pure: no clock, no I/O.
//
// Runner contract (see CONTRACT_CHANGES.md "Flow runtime semantics"):
// - `.tick(t)` carries a monotonic clock in seconds; the first tick only sets the reference.
// - `.listen` means: wait for speech to finish (max ~3 s), beep, record. The session never emits its own beep.
// - An empty or silent recording must arrive as `.notUnderstood(noisy:)`; a cancelled one sends nothing.
// - `.motion` yaw grows clockwise (turning right), like `clockPosition(degreesRight:)`.
// - Danger lines are spoken by the safety lane; stairs lines come from here as `.say(_, .stairs)`.
// - The session has no database: `.setTarget` always carries `candidates: []`; the runner fills them.

public struct ShoppingSession {
    public internal(set) var state = SessionState()
    let catalog: [String: AisleInfo]
    let destinationWords: [Destination: [String]]
    /// Effects of the event being handled.
    var out: [Effect] = []
    /// Lines spoken for the event being handled (`prompt` = counts as the last prompt for "repeat").
    var spoken: [(text: String, prompt: Bool)] = []

    public init(catalog: [String: AisleInfo]) {
        self.init(catalog: catalog, destinations: SessionTuning.defaultDestinations)
    }

    /// `destinations`: keywords from synonyms.json (`Catalog.destinations`).
    public init(catalog: [String: AisleInfo], destinations: [Destination: [String]]) {
        self.catalog = catalog
        self.destinationWords = destinations.isEmpty ? SessionTuning.defaultDestinations : destinations
    }

    public mutating func handle(_ e: SessionEvent) -> [Effect] {
        out = []
        spoken = []
        dispatch(e)
        if !spoken.isEmpty {
            state.lastLine = spoken.map(\.text).joined(separator: " ")
            let prompts = spoken.filter(\.prompt).map(\.text)
            if !prompts.isEmpty { state.lastPrompt = prompts.joined(separator: " ") }
        }
        let effects = out
        out = []
        spoken = []
        return effects
    }
}

// MARK: - Dispatch

extension ShoppingSession {
    mutating func dispatch(_ e: SessionEvent) {
        switch e {
        case .started: start()
        case .talkPressed: talkPressed()
        case .donePressed: if state.isListening { out.append(.finishListening) }
        case .routed(let request):
            recordingEnded()
            handleRequest(request)
            afterRecording()
        case .notUnderstood(let noisy):
            recordingEnded()
            notUnderstood(noisy: noisy)
            afterRecording()
        case .tick(let t): tick(t)
        case .motion(let yaw, let steps, let walking): motion(yaw: yaw, steps: steps, walking: walking)
        case .danger(let cut): danger(cutRecording: cut)
        case .dangerCleared: dangerCleared()
        case .stairs(let o): stairs(o)
        case .askAnswer(let answer): askAnswer(answer)
        case .productLookedUp(let goal):
            if state.isListening { hold(e, goalBound: false) } else { productLookedUp(goal) }
        case .surroundings(let text):
            if state.isListening { hold(e, goalBound: false) } else { surroundings(text) }
        case .system(let s):
            if state.isListening && Self.isNotice(s) { hold(e, goalBound: false) } else { system(s) }
        case .signs(let signs): signsSeen(signs)
        case .doors(let doors): if canObserve { doorsSeen(doors) }
        case .pointed(let p): if canObserve { pointed(p) }
        case .positioning(let hint): if canObserve { positioning(hint) }
        case .outside(let isOutside):
            if state.step == .paused { return }
            if observationsHeld { hold(e, goalBound: false) } else { setOutside(isOutside, saidByUser: false) }
        case .entrancePicked, .aisleVerdict, .arrivedAtAisle, .arrivedAtDestination, .confirmed:
            if state.step == .paused { return }
            if observationsHeld {
                if case .confirmed(nil, _) = e { return }       // "unclear" frames carry nothing to replay
                hold(e, goalBound: true)
                return
            }
            observe(e)
        }
    }

    mutating func observe(_ e: SessionEvent) {
        switch e {
        case .entrancePicked(let pick): entrancePicked(pick)
        case .aisleVerdict(let aisle, let evidence): aisleVerdict(aisle, evidence: evidence)
        case .arrivedAtAisle(let clock): arrivedAtAisle(clock: clock)
        case .arrivedAtDestination: arrivedAtDestination()
        case .confirmed(let info, let isGoal): confirmed(info, isGoal: isGoal)
        default: break
        }
    }

    static func isNotice(_ s: SystemEvent) -> Bool {
        switch s {
        case .batteryLow, .thermal, .audioRouteChanged, .cameraDenied, .micDenied: return true
        case .backgrounded, .foregrounded, .online: return false
        }
    }

    /// Transitions wait while the user talks or an Ask answer is pending (guidance paused, §5.10, §5.11).
    var observationsHeld: Bool { state.isListening || state.step == .asking }
    var canObserve: Bool { !observationsHeld && state.step != .paused }
    /// Repeating prompts and timer lines stay quiet.
    var guidanceHeld: Bool {
        observationsHeld || state.step == .paused || state.dangerSince != nil || state.thermal == .critical
    }
    var hasActiveGoal: Bool { state.goal != nil || state.destination != nil }

    mutating func hold(_ e: SessionEvent, goalBound: Bool) {
        if state.held.last?.event == e { return }
        state.held.append(SessionHeldEvent(event: e, epoch: state.goalEpoch, goalBound: goalBound))
        if state.held.count > SessionTuning.maxHeld { state.held.removeFirst(state.held.count - SessionTuning.maxHeld) }
    }

    mutating func replayHeld() {
        guard !state.held.isEmpty, !observationsHeld else { return }
        let events = state.held
        state.held = []
        for h in events where !h.goalBound || h.epoch == state.goalEpoch { dispatch(h.event) }
    }
}

// MARK: - Start, talking, recalculate

extension ShoppingSession {
    mutating func start() {
        guard state.step == .idle || state.step == .sessionDone else { return }
        var fresh = SessionState()
        fresh.online = state.online
        fresh.verbosity = state.verbosity
        fresh.thermal = state.thermal
        fresh.outside = state.outside
        fresh.isWalking = state.isWalking
        fresh.now = state.now
        fresh.lastTick = state.lastTick
        fresh.yaw = state.yaw
        fresh.steps = state.steps
        fresh.hasMotion = state.hasMotion
        fresh.work = state.work
        fresh.stairs = state.stairs
        fresh.speech.notices = state.speech.notices
        fresh.goalEpoch = state.goalEpoch + 1
        state = fresh
        enter(.askingGoal)
        announce(SessionPhrases.askGoal)
        listen(SessionTuning.talkSeconds)
    }

    /// Volume up / screen Talk (the runner applies the walking and screen rules first).
    mutating func talkPressed() {
        if state.isListening {
            out.append(.finishListening)                       // pressed again = done; never restarts the recording
            return
        }
        if state.step == .asking {                             // the new recording replaces the pending question
            state.askStartedAt = nil
            resumePausedStep()
        }
        out.append(.stopSpeech)
        listen(SessionTuning.talkSeconds)
    }

    mutating func listen(_ seconds: Double) {
        out.append(.listen(maxSeconds: seconds))
        state.isListening = true
        state.listenDeadline = state.now + seconds + SessionTuning.listenSlack
    }

    mutating func recordingEnded() {
        state.isListening = false
        state.listenDeadline = nil
        if state.step == .paused, state.pauseReason == .lost {
            resumePausedStep()
            noteEvidence()
        }
    }

    /// Every recording ends with resume + recalculate (§5.10).
    mutating func afterRecording() {
        replayHeld()
        recalculate()
    }

    /// Clear the de-dupe so the next observation speaks a fresh prompt; restart the short "nothing seen" prompts.
    mutating func recalculate() {
        state.speech.lastGuidance = nil
        state.marks.scanAnchor = state.now
        state.marks.scanPrompted = false
        state.marks.lastDirectionAt = nil
        state.marks.lastOtherSignsAt = nil
        state.marks.lastPointCueAt = nil
        emitWork()
    }

    mutating func resumePausedStep() {
        var s = state.resumeStep ?? (hasActiveGoal ? .findingSignage : .idle)
        if s == .asking || s == .paused { s = .idle }
        state.step = s
        state.resumeStep = nil
        state.pauseReason = nil
        emitWork()
    }

    mutating func noteEvidence() {
        state.progress.evidenceAt = state.now
        state.progress.lostTrackAt = nil
    }
}

// MARK: - Steps and stream work (§3.6)

extension ShoppingSession {
    mutating func enter(_ s: Step) {
        state.step = s
        state.stepStartedAt = state.now
        state.marks = SessionStepMarks(anchor: state.now)
        switch s {
        case .walkingAisle, .pointing, .holdUpToCheck:
            if let c = state.goal?.category { state.currentAisle = c }
            if state.progress.aisleEnteredAt == nil {
                state.progress.aisleEnteredAt = state.now
                markAisleEntry()
            }
        case .findingEntrance, .findingSignage, .shelfVote, .findingDestination, .sessionDone, .idle:
            state.currentAisle = nil
        default:
            break
        }
        emitWork()
    }

    mutating func enterPointing(prompt: Bool) {
        enter(.pointing)
        if prompt { announce(SessionPhrases.pointAtShelf) }
    }

    mutating func markAisleEntry() {
        state.progress.entryYaw = state.yaw
        state.progress.entrySteps = state.steps
        state.progress.turnBackSteps = nil
    }

    mutating func emitWork() {
        let w = work(for: state.step)
        if state.work != w {
            state.work = w
            out.append(.setWork(w))
        }
    }

    /// shelfMode is on from "Turn to the shelf" through pointing and hold-up (§5.3), and stays on while asking about the held item.
    func work(for step: Step) -> StreamWork {
        var w: StreamWork
        switch step {
        case .findingEntrance, .findingSignage, .walkingAisle, .shelfVote, .findingDestination:
            w = StreamWork(text: .fast, yoloFPS: 10)
        case .pointing:
            w = StreamWork(text: .fast, hands: true, yoloFPS: 10, shelfMode: true)
        case .holdUpToCheck:
            w = StreamWork(text: .accurate, barcodes: true, yoloFPS: 10, shelfMode: true)
        case .asking:
            let paused = state.resumeStep.flatMap { $0 == .asking ? nil : $0 } ?? .idle
            w = StreamWork(text: .off, yoloFPS: 10, shelfMode: work(for: paused).shelfMode)
        case .idle, .askingGoal, .sessionDone, .paused:
            w = StreamWork(text: .off, yoloFPS: 10)
        }
        switch state.thermal {
        case .serious: w.yoloFPS = 5                                        // YOLO first, then OCR; danger last
        case .critical: w = StreamWork(text: .off, yoloFPS: 5, shelfMode: w.shelfMode)   // danger + stairs only
        case .nominal, .fair: break
        }
        return w
    }
}

// MARK: - Speech

extension ShoppingSession {
    /// A repeating or timer-driven prompt: quiet while guidance is held; `dedupe` skips a repeat of the last line.
    @discardableResult
    mutating func guide(_ text: String, dedupe: Bool = false, repeatAfter: Double = .infinity) -> Bool {
        guard !guidanceHeld else { return false }
        if dedupe, state.speech.lastGuidance == text, state.now - state.speech.lastGuidanceAt < repeatAfter { return false }
        announce(text)
        return true
    }

    /// A flow line tied to a transition (always spoken).
    mutating func announce(_ text: String) {
        state.speech.lastGuidance = text
        state.speech.lastGuidanceAt = state.now
        speak(text, .guidance, prompt: true)
    }

    /// Optional line, dropped at the brief detail level (§5.15).
    mutating func narrate(_ text: String) {
        guard state.verbosity > .brief else { return }
        speak(text, .narration, prompt: true)
    }

    /// Answer to something the user said.
    mutating func reply(_ text: String, prompt: Bool = true) {
        speak(text, .reply, prompt: prompt)
    }

    mutating func speak(_ text: String, _ priority: SpeechPriority, prompt: Bool) {
        guard !text.isEmpty else { return }
        out.append(.say(text, priority))
        spoken.append((text, prompt))
    }
}
