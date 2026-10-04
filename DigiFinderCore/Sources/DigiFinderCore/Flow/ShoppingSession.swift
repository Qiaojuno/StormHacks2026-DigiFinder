// Shopping flow state machine (§5): (state, event) -> (state, [Effect]). Pure: no clock, no I/O.
//
// Runner contract (also documented on `SessionEvent` / `Effect` in Contracts/Session.swift):
// - `.tick(t)` carries a monotonic clock in seconds; the first tick only sets the reference.
// - `.listen` means: wait for speech to finish (max ~3 s), beep, record. The session never emits its own beep.
// - An empty or silent recording must arrive as `.notUnderstood(noisy:)`; a cancelled one sends nothing.
// - `.motion` yaw grows clockwise (turning right), like `clockPosition(degreesRight:)`.
// - Danger lines are spoken by the safety lane; stairs lines come from here as `.say(_, .stairs)`.
// - The session has no database: `.setTarget` always carries `candidates: []`; the runner fills them.
// - Setup choices arrive through `setVerbosity`, `setDistanceInSteps` and `setOnlineHelp` (not events).

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

// MARK: - Settings (setup sheet, §5.13)

extension ShoppingSession {
    /// Detail level from setup; "quieter" / "more detail" change it too.
    public mutating func setVerbosity(_ v: Verbosity) { state.verbosity = v }
    /// Spoken distances in steps (~0.7 m each) instead of meters.
    public mutating func setDistanceInSteps(_ on: Bool) { state.distanceInSteps = on }
    /// Settings "Nearby mode": on forces the not-a-store search (skips the Gemini check); off goes back to automatic.
    public mutating func setNearbyMode(_ on: Bool) -> [Effect] {
        out = []
        spoken = []
        setPlaceOverride(on ? .general : nil)
        let effects = out
        out = []
        spoken = []
        return effects
    }
    /// false without Secrets.plist (no Gemini): questions, the entrance pick and the grocery check take the offline path.
    public mutating func setOnlineHelp(_ available: Bool) { state.onlineHelp = available }
    /// See `SessionState.onDeviceItemSearch` (off in the app).
    public mutating func setOnDeviceItemSearch(_ on: Bool) { state.onDeviceItemSearch = on }
}

// MARK: - Dispatch

extension ShoppingSession {
    mutating func dispatch(_ e: SessionEvent) {
        switch e {
        case .started: start()
        case .talkPressed: talkPressed()
        case .recordingCancelled:
            if state.isListening {
                recordingEnded()
                afterRecording()
            }
        case .donePressed: stopStream()                    // volume down / stop: everything stops (owner decision)
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
        case .pathClear(let meters): pathClear(meters: meters)
        case .itemSeen(let clock, let distance): if canObserve { itemSeen(clock: clock, distance: distance) }
        case .searchHint(let text): if canObserve { searchHint(text) }    // never held: a stale hint is useless
        case .stairs(let o): stairs(o)
        case .assistAnswer(let say, let find): assistAnswer(say: say, find: find)
        case .unmatched(let text, let noisy):
            recordingEnded()
            unmatched(text, noisy: noisy)
            afterRecording()
        case .placeClassified(let answer): placeClassified(answer)
        case .productLookedUp(let goal):
            if state.isListening { hold(e, goalBound: false) } else { productLookedUp(goal) }
        case .surroundings(let text):
            if state.isListening { hold(e, goalBound: false) } else { surroundings(text) }
        case .system(let s):
            if state.isListening && Self.isNotice(s) { hold(e, goalBound: false) } else { system(s) }
        case .signs(let signs): signsSeen(signs)
        case .doors(let doors): if canObserve { doorsSeen(doors) }
        case .pointed(let p): if canObserve { pointed(p) }
        case .shelfDistance(let m): if canObserve { shelfDistance(m) }
        case .positioning(let hint): if canObserve { positioning(hint) }
        case .outside(let isOutside):
            if state.pause != nil { return }
            if observationsHeld { hold(e, goalBound: false) } else { setOutside(isOutside, saidByUser: false) }
        case .entrancePicked, .aisleVerdict, .arrivedAtAisle, .arrivedAtDestination, .confirmed, .aisleEnd:
            if state.pause != nil { return }
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
        case .aisleEnd: aisleEndSeen()
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
    var observationsHeld: Bool { state.isListening || state.askPending }
    var canObserve: Bool { state.streaming && !observationsHeld && state.pause == nil }
    /// Repeating prompts and timer lines stay quiet (also while "Switch to milk, or add it?" awaits an answer).
    var guidanceHeld: Bool {
        !state.streaming || observationsHeld || state.pause != nil || state.dangerSince != nil || state.thermal == .critical
            || state.pendingChoice != nil
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
        guard state.step == .idle, !hasActiveGoal, !state.askPending, state.pause == nil else { return }
        var fresh = SessionState()
        fresh.online = state.online
        fresh.verbosity = state.verbosity
        fresh.distanceInSteps = state.distanceInSteps
        fresh.onlineHelp = state.onlineHelp
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
        fresh.place = state.place
        fresh.placeOverride = state.placeOverride
        fresh.placeCheck = state.placeCheck
        fresh.placeDecidedAt = state.placeDecidedAt
        fresh.placeConfidence = state.placeConfidence
        fresh.placeScene = state.placeScene
        fresh.placeTries = state.placeTries
        fresh.onDeviceItemSearch = state.onDeviceItemSearch
        fresh.speech.notices = state.speech.notices
        fresh.goalEpoch = state.goalEpoch + 1
        state = fresh
        // Owner decision: the app opens stopped (camera, danger, checks off) and silent apart from one hint.
        // The first volume up starts the stream, records, and runs the grocery check (`talkPressed`).
        state.streaming = false
        enter(.idle)
        out.append(.setStreaming(false))
        announce(SessionPhrases.pressToStart)
    }

    /// First start of the stream after app open: where the user is (once). The place line is said after the
    /// request recorded with it has been handled.
    mutating func checkPlaceOnFirstStart() {
        guard state.placeOverride == nil, state.placeDecidedAt == nil, state.placeCheck == nil else { return }
        state.openingPending = true                        // say the place line once it's decided
        if state.onlineHelp {
            requestPlaceCheck()
        } else {
            placeDecided(.general, line: SessionPhrases.couldntTellPlace)   // no Gemini: general
        }
    }

    /// Volume down / the stop button (owner decision): the stream ends at once. Recording is discarded, speech and
    /// prompts stop, perception and danger stop (runner), and the item and list are cleared. Silent.
    mutating func stopStream() {
        guard state.streaming || state.isListening else { return }
        if state.isListening { out.append(.cancelListening) }
        state.isListening = false
        state.streaming = false
        state.goal = nil
        state.queue = []
        state.destination = nil
        state.pendingChoice = nil
        state.choiceAskedAt = nil
        state.askingNext = false
        state.askingNextAt = nil
        state.assist = nil
        state.askPending = false
        state.held = []
        state.placeCheck = nil
        state.openingPending = false
        state.pendingPlaceLine = nil
        state.loadingGoal = false
        state.dangerSince = nil
        state.goalEpoch += 1
        out.append(.setTarget(nil, candidates: [], destination: nil))
        out.append(.setStreaming(false))
        enter(.idle)
    }

    /// Volume up / record button: only starts a recording (ignored while one runs). Volume down ends it (§5.10).
    mutating func talkPressed() {
        guard !state.isListening else { return }
        if !state.streaming {                                  // volume up when stopped: the stream starts
            state.streaming = true
            out.append(.setStreaming(true))
        }
        if state.askPending {                                  // the new recording replaces the pending request
            state.assist = nil
            state.askPending = false
            emitWork()
        }
        out.append(.stopSpeech)
        listen()
        checkPlaceOnFirstStart()
    }

    /// Records until volume down: no silence end, no time limit.
    mutating func listen() {
        state.listenStartedAt = state.now
        out.append(.listen)
        state.isListening = true
    }

    mutating func recordingEnded() {
        state.isListening = false
        if state.pause == .lost {
            state.pause = nil
            emitWork()
            noteEvidence()
        }
    }

    /// Every recording ends with resume + recalculate (§5.10).
    mutating func afterRecording() {
        if let line = state.pendingPlaceLine {                 // the place line follows the user's request
            state.pendingPlaceLine = nil
            announce(line)
        }
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

    mutating func noteEvidence() {
        state.progress.evidenceAt = state.now
        state.progress.lostTrackAt = nil
    }
}

// MARK: - Phases and stream work (§3.6)

extension ShoppingSession {
    /// Phase change. Silent: the caller speaks only when the user must act.
    mutating func enter(_ s: Step) {
        state.step = s
        state.stepStartedAt = state.now
        state.marks = SessionStepMarks(anchor: state.now)
        state.pendingPick = nil
        state.vote = nil
        if s != .findAisle { state.aisleBearing = nil }
        switch s {
        case .inAisle, .pick, .confirm:
            if let c = state.goal?.category { state.currentAisle = c }
            if state.progress.aisleEnteredAt == nil {
                state.progress.aisleEnteredAt = state.now
                markAisleEntry()
            }
        case .entrance, .findAisle:
            state.currentAisle = nil
        case .idle:
            break                                           // "What's next?" at the shelf keeps the aisle
        }
        emitWork()
    }

    /// Item search phase for the current goal or destination.
    mutating func enterFindAisle() {
        enter(.findAisle)
        state.itemSeenAt = nil
        state.itemClock = nil
        state.itemDistance = nil
        if state.goal != nil && isGeneral { guide(SessionPhrases.turnSlowly) }
    }

    mutating func markAisleEntry() {
        state.progress.entryYaw = state.yaw
        state.progress.entrySteps = state.steps
    }

    mutating func emitWork() {
        let w = currentWork()
        if state.work != w {
            state.work = w
            out.append(.setWork(w))
        }
    }

    /// Perception work per phase: Entrance / FindAisle / InAisle read signs (and look for the item), Pick points,
    /// Confirm reads the held item. Overlays (Ask pending, paused) turn the camera work off. Nothing here affects
    /// obstacle alerts: those follow the motion state only.
    func currentWork() -> StreamWork {
        var w: StreamWork
        if state.pause != nil || state.askPending {
            w = StreamWork(text: .off, yoloFPS: 10)
        } else {
            switch state.step {
            case .entrance, .findAisle, .inAisle: w = StreamWork(text: .fast, yoloFPS: 10)
            case .pick: w = StreamWork(text: .fast, hands: true, yoloFPS: 10)
            case .confirm: w = StreamWork(text: .accurate, barcodes: true, yoloFPS: 10)
            case .idle: w = StreamWork(text: .off, yoloFPS: 10)
            }
        }
        switch state.thermal {
        case .serious: w.yoloFPS = 5                                        // YOLO first, then OCR; danger last
        case .critical: w = StreamWork(text: .off, yoloFPS: 5)              // danger + stairs only
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
