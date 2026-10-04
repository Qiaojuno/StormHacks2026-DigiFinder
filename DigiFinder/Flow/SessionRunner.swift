import CoreGraphics
import Foundation
import DigiFinderCore

/// The coordinator (§3.1): the only place effects run. Owns `ShoppingSession`, turns service output, system events,
/// motion (~2 Hz) and a monotonic clock (`.tick`, ~2 Hz) into `SessionEvent`s, and performs every `Effect`.
///
/// Threads: everything here runs on the main actor. Service callbacks hop to main before they reach the session.
/// The safety lane never waits on this: `SafetyService` vibrates and speaks the alert itself on its own queue, and
/// only then reports `.danger` here. Network, stills, JPEG encoding and "What's around?" run off the main thread.
@MainActor
final class SessionRunner: UISessionDriving, UIDebugSnapshotSource {
    /// step, last spoken line, isWalking
    var onUpdate: ((Step, String, Bool) -> Void)?
    /// Recording started / ended (the record button's state).
    var onListeningChange: ((Bool) -> Void)?
    private var lastListening = false

    /// Clock and motion rate (§3.3: `.tick` every ~0.5 s, `.motion` ~2 Hz).
    static let tickInterval = 0.5
    /// Never record while speaking: wait this long at most for speech to end before listening (§5.10).
    static let maxSpeechWait = 3.0
    /// A cancelled recording takes a moment to wind down before the next one can start.
    static let maxRecorderWait = 1.0

    private let env: AppEnvironment
    private var session: ShoppingSession
    private let resolver: DataGoalResolver
    private let router: RequestRouter

    private var started = false
    private var sessionStarted = false
    private var walkthroughTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    /// Bumped whenever a recording is cancelled or replaced; a stale recording's result is dropped.
    private var listenGeneration = 0
    private var appliedSettings: UISettings?
    private var feedbackVerbosity: Verbosity?
    private var lastUpdate: (step: Step, line: String, walking: Bool)?
    private var foundGoals: [Goal] = []

    // Read by the debug overlay from any thread.
    private nonisolated(unsafe) let safetyDebug: SafetyService
    private nonisolated(unsafe) let perceptionDebug: PerceptionService
    private let notes = SessionRunnerNotes()
    /// Gemini item finder (owner decision); nil without Gemini.
    private let finder: SessionGeminiFinder?
    private let finderStatus: SessionGeminiFinderStatus?

    init(env: AppEnvironment) {
        self.env = env
        let resolver = DataGoalResolver(products: env.products, catalog: env.catalog)
        self.resolver = resolver
        router = RequestRouter(productSearch: { resolver.goals(for: $0) }, destinations: env.catalog.destinations,
                               synonyms: env.catalog.synonyms)
        var session = ShoppingSession(catalog: env.catalog.aisles, destinations: env.catalog.destinations)
        session.setOnlineHelp(env.gemini != nil)
        self.session = session
        safetyDebug = env.safety
        perceptionDebug = env.perception
        let finder = env.gemini.map { SessionGeminiFinder(gemini: $0, perception: env.perception, system: env.system) }
        self.finder = finder
        finderStatus = finder?.status
    }

    // MARK: - Frozen API

    /// Idempotent. Start order: motion, system, frames, perception, then safety (its depth handler runs first).
    func start() {
        guard !started else { return }
        started = true
        wireServices()
        env.voice.contextualStrings = Self.recognitionHints(env.catalog)

        env.motion.start()
        env.system.start()
        // The camera runs whenever the app is open: the volume buttons only reach the app while a capture session is
        // running (AVCaptureEventInteraction), and the Home screen shows the live view. "Stopped" turns off checking,
        // danger and prompts, not the camera.
        startCamera()
        env.perception.start()
        env.safety.start()
        startClock()

        let voice = env.voice
        Task { _ = await voice.requestPermissions() }        // a denial arrives through onPermissionDenied

        if walkthroughTask == nil { beginSession() }        // else the walkthrough starts it when it ends
        publish()
    }

    /// Volume up (owner decision): only records a request; stopped → "Press volume down to start." 
    func volumeUp() {
        if skipWalkthrough() { return }
        handle(.talkPressed)
    }

    /// Volume down (owner decision): starts the stream when stopped; when running, everything stops — recording
    /// discarded, speech cut, camera, danger and perception off, item cleared.
    func volumeDown() {
        if skipWalkthrough() { return }
        handle(.donePressed)
    }

    /// On-screen record button (owner decision): same as volume down (start / stop the stream).
    func screenTalkPressed() {
        volumeDown()
    }

    private func startCamera() {
        do {
            try env.frames.start()
        } catch {
            // Only a refused permission gets "Camera access is off…"; a configuration failure just shows
            // "Camera unavailable" (danger can't run; the line would send the user to Settings for nothing).
            if CapturePermission.isDenied { handle(.system(.cameraDenied)) }
        }
    }

    /// Stream state for the record button (true = shows stop).
    var onStreamingChange: ((Bool) -> Void)?
    var isStreaming: Bool { session.state.streaming }

    /// Turns the whole stream on or off: camera, danger, perception; off also cuts every recording and line.
    private func setStreaming(_ on: Bool) {
        if on {
            startCamera()                                    // no-op when already running
            env.safety.setActive(true)
            env.perception.setActive(true)
        } else {
            listenGeneration += 1
            env.voice.cancel()
            env.feedback.stopAll()
            env.safety.setActive(false)
            env.perception.setActive(false)
            // The camera keeps running: it carries the volume buttons and the live view.
        }
        onStreamingChange?(on)
    }

    // MARK: - UISessionDriving

    func submitTypedRequest(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let typed = env.voice as? TypedVoiceInput, typed.isListening {
            typed.submit(t)                                  // ends the running recording with this text
            return
        }
        if session.state.isListening || env.voice.isListening {
            listenGeneration += 1
            env.voice.cancel()
        }
        route(t, noisy: false)
    }

    func inject(_ event: SessionEvent) {
        if case .danger = event {
            env.feedback.danger("Person", steer: .clock(1), distance: nil, vibrate: true)   // as the safety lane would
            let cut = env.voice.isListening
            if cut {
                listenGeneration += 1
                env.voice.cancel()
            }
            handle(.danger(cutRecording: cut))
            return
        }
        handle(event)
    }

    func speakScreenText(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        env.feedback.stopSpeech()                            // replaces the previous screen line
        env.feedback.say(t, .reply)
    }

    func speakWalkthrough(_ lines: [String]) {
        walkthroughTask?.cancel()
        let feedback = env.feedback
        walkthroughTask = Task { [weak self] in
            for line in lines {
                guard !Task.isCancelled else { return }
                feedback.say(line, .reply)
                await Self.waitWhileSpeaking(feedback, maxSeconds: 30)   // one at a time: queued lines go stale
            }
            guard !Task.isCancelled else { return }
            self?.walkthroughEnded()
        }
    }

    func apply(settings s: UISettings) {
        let old = appliedSettings
        appliedSettings = s
        let feedback = env.feedback
        if old?.speechSpeed != s.speechSpeed { feedback.speechRate = s.speechSpeed.rate }
        if old == nil || old?.voiceIdentifier != s.voiceIdentifier { feedback.voiceIdentifier = s.voiceIdentifier }
        if old?.tonesEnabled != s.tonesEnabled { feedback.tonesEnabled = s.tonesEnabled }
        if old?.dangerHapticsEnabled != s.dangerHapticsEnabled { feedback.dangerHapticsEnabled = s.dangerHapticsEnabled }
        if old?.units != s.units {
            session.setDistanceInSteps(s.units == .steps)
            feedback.distanceInSteps = s.units == .steps
        }
        if old?.nearbyMode != s.nearbyMode {                 // "it's nearby" / "store mode" change it too
            perform(session.setNearbyMode(s.nearbyMode))
        }
        if old?.detail != s.detail {                          // "quieter" / "more detail" change it too
            session.setVerbosity(s.detail)
            syncVerbosity()
        }
    }

    // MARK: - UIDebugSnapshotSource

    nonisolated var debugSnapshot: UIDebugSnapshot {
        let perception = perceptionDebug.debugSnapshot
        var snap = Self.snapshot(safety: safetyDebug.debugSnapshot, perception: perception)
        let finderLine = finderStatus?.line(tracking: perception.trackedBox != nil) ?? "Gemini finder off (not configured)"
        snap.notes = notes.lines + [finderLine] + snap.notes
        return snap
    }

    // MARK: - Events

    private func handle(_ e: SessionEvent) {
        if case .system(.thermal(let level)) = e { env.frames.setThermalLevel(level) }   // §5.16 capture hook
        perform(session.handle(e))
    }

    private func wireServices() {
        // Safety lane: haptics and the alert line already happened on the capture queue; only then hop to main.
        env.safety.onEvent = { [weak self] e in Self.onMain { self?.handle(e) } }
        env.perception.onEvent = { [weak self] e in Self.onMain { self?.handle(e) } }
        finder?.onEvent = { [weak self] e in self?.handle(e) }      // already on the main actor
        env.system.onEvent = { [weak self] e in Self.onMain { self?.handle(.system(e)) } }
        env.voice.onPermissionDenied = { [weak self] in Self.onMain { self?.handle(.system(.micDenied)) } }
        env.frames.onCapabilitiesChange = { [weak self] caps in
            guard !caps.cameraAvailable else { return }
            let denied = CapturePermission.isDenied
            Self.onMain {
                if denied { self?.handle(.system(.cameraDenied)) }
                self?.publish()
            }
        }
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.clockFired()
                try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
            }
        }
    }

    /// Which way up the phone hangs, from gravity (owner decision: automatic, no flip button).
    private var orientation = OrientationTracker()

    private func clockFired() {
        let m = env.motion
        if let upsideDown = orientation.update(gravityY: m.gravity.y, t: ProcessInfo.processInfo.systemUptime) {
            orientationChanged(upsideDown)
        }
        handle(.motion(yawDegrees: -m.yawDegrees, steps: m.steps, walking: m.isWalking))   // session yaw is clockwise
        handle(.tick(ProcessInfo.processInfo.systemUptime))
    }

    /// Every camera-image direction (item box, tracker, signs, Gemini photos) follows the new way up at once.
    /// LiDAR alerts use gravity directly and need nothing. The tracked box and any Gemini answer for a photo taken
    /// the old way up are dropped; the next scan (≤ 2 s) finds the item again.
    private func orientationChanged(_ upsideDown: Bool) {
        CaptureOrientation.set(upsideDown: upsideDown)
        if env.perception.isTrackingTarget { env.perception.trackTarget(nil) }
        finder?.restart()
    }

    private func beginSession() {
        guard started, !sessionStarted else { return }
        sessionStarted = true
        handle(.started)
    }

    private func walkthroughEnded() {
        walkthroughTask = nil
        beginSession()
    }

    /// A talk press during the first-launch walkthrough skips the rest and opens the session.
    private func skipWalkthrough() -> Bool {
        guard let task = walkthroughTask else { return false }
        task.cancel()
        walkthroughTask = nil
        env.feedback.stopSpeech()
        guard started, !sessionStarted else { return false }
        beginSession()
        return true
    }

    // MARK: - Effects

    private func perform(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .say(let text, let priority):
                env.feedback.say(text, priority)
            case .stopSpeech:
                env.feedback.stopSpeech()
            case .setStreaming(let on):
                setStreaming(on)
            case .buzz:
                env.feedback.dangerPulse()
            case .chime(let tone):
                env.feedback.chime(tone)
            case .listen:
                listen()
            case .finishListening:
                env.voice.finish()
            case .cancelListening:
                listenGeneration += 1                         // a cancelled recording sends nothing
                env.voice.cancel()
            case .setWork(let w):
                env.safety.setWork(w)
                env.perception.setWork(w)
                env.frames.setRates(Self.captureRates(for: w))
            case .setTarget(let goal, _, let destination):
                let candidates = goal.map { resolver.candidates(for: $0) } ?? []
                env.perception.setTarget(goal, candidates: candidates, destination: destination)
            case .assist(let text, let context):
                assist(text, context: context)
            case .classifyPlace:
                classifyPlace()
            case .pickEntrance:
                pickEntrance()
            case .lookupProduct(let words):
                lookupProduct(words)
            case .describeSurroundings:
                describeSurroundings()
            case .remember(let product):
                let perception = env.perception
                Self.background(.utility) { perception.remember(product) }
            case .markDone(let goal):
                foundGoals.append(goal)
            }
        }
        syncVerbosity()
        syncFinder()
        syncThreatProfile()
        publish()
    }

    private var threatProfile: ThreatProfile?

    /// Owner decision: grocery store = sensitive alerts; anywhere else or not known yet = calm (crowds, schools).
    private func syncThreatProfile() {
        let st = session.state
        let p: ThreatProfile = (st.placeOverride ?? st.place) == .store ? .store : .general
        guard p != threatProfile else { return }
        threatProfile = p
        env.safety.setProfile(p)
    }

    /// The Gemini item finder runs while a search runs: stream on, a goal, Entrance / FindAisle / InAisle, no Ask
    /// pending, not paused. Any change (goal, phase, stop) restarts or ends its loop.
    private func syncFinder() {
        guard let finder else { return }
        let st = session.state
        let searching = st.streaming && !st.askPending && st.pause == nil
            && [Step.entrance, .findAisle, .inAisle, .confirm].contains(st.step)
            && (st.step != .confirm || !st.onDeviceItemSearch)          // Confirm: Gemini held-item check
        finder.update(searching ? st.goal.map { SessionGeminiFinder.Search(goal: $0, step: st.step) } : nil)
    }

    /// Stream B delivery for the step (§3.6): pointing needs ≥ 10 fps for hand pose; otherwise YOLO's rate is enough.
    /// Thermal caps (`setThermalLevel`) are applied on top by the frame source.
    static func captureRates(for w: StreamWork) -> CaptureRates {
        let yolo = Double(max(w.yoloFPS, 5))
        return CaptureRates(streamBFPS: w.hands ? max(20, yolo) : yolo + 2, depthFPS: CaptureRates.full.depthFPS)
    }

    // MARK: Listening (§5.10)

    /// Records until volume down (no silence end, no time limit).
    private func listen() {
        listenGeneration += 1
        let generation = listenGeneration
        let voice = env.voice
        let feedback = env.feedback
        listenTask = Task { [weak self] in
            await Self.waitWhile(maxSeconds: Self.maxRecorderWait) { voice.isListening }
            await Self.waitWhileSpeaking(feedback, maxSeconds: Self.maxSpeechWait)   // listen then beeps itself
            guard let self, generation == self.listenGeneration else { return }
            let result = await voice.listen()
            guard generation == self.listenGeneration else { return }
            self.recordingEnded(result)
        }
    }

    private func recordingEnded(_ result: VoiceResult) {
        switch result {
        case .cancelled: handle(.recordingCancelled)         // silent; the session stops waiting for a transcript
        case .empty(let noisy): handle(.notUnderstood(noisy: noisy))
        case .text(let text, let noisy): route(text, noisy: noisy)
        }
    }

    /// The offline router decides (§5.2). Words it can't place go to the session as `.unmatched` (Gemini when
    /// online); a noisy "unknown item" is treated the same way rather than becoming a goal.
    private func route(_ text: String, noisy: Bool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch router.route(t) {
        case nil:
            handle(t.isEmpty ? .notUnderstood(noisy: noisy) : .unmatched(t, noisy: noisy))
        case .unknownProduct? where noisy:
            handle(.unmatched(t, noisy: true))
        case let request?:
            handle(.routed(request))
        }
    }

    // MARK: Online (§5.11, §5.2)

    /// Something unusual the user said: transcript + one still + context to Gemini, silently (§5.11).
    /// `findItem` is resolved like a spoken product (database / household words), else a word-search goal.
    private func assist(_ text: String, context: AssistContext) {
        guard let gemini = env.gemini else {
            handle(.assistAnswer(say: nil, find: nil))
            return
        }
        let frames = env.frames
        let router = self.router
        Task { [weak self] in
            var answer: GeminiAssist?
            if let jpeg = await Self.uprightJPEG(frames) {
                answer = try? await gemini.assist(text, context: context, still: jpeg)
            }
            let goal = answer?.findItem.map { Self.goal(forItem: $0, router: router) }
            self?.handle(.assistAnswer(say: answer?.say, find: goal))
        }
    }

    /// "oat milk" → the router's goal for those words; nothing known → a word-search goal.
    static func goal(forItem item: String, router: RequestRouter) -> Goal {
        switch router.route(item) {
        case .product(let g, _)?: return g
        case .products(let gs, _)?: return gs.first ?? Goal(product: item)
        default: return Goal(product: item)
        }
    }

    /// Grocery store or anywhere else, once at app open (and once more when unsure): a good moment, 3 stills, one
    /// Gemini request. Offline, no camera or no Gemini → nil (the session says so and takes the store flow).
    private func classifyPlace() {
        let frames = env.frames
        let motion = env.motion
        let gemini = env.gemini
        let system = env.system
        Task { [weak self] in
            var answer: PlaceAnswer?
            if let gemini {
                // Photos first: the network monitor has had time to report by then.
                let stills = await SessionPlacePhotos.take(frames: frames, motion: motion)
                if !stills.isEmpty, system.isOnline { answer = (try? await gemini.classifyPlace(stills: stills)) ?? nil }
            }
            self?.handle(.placeClassified(answer))
        }
    }

    private func pickEntrance() {
        guard let gemini = env.gemini else {
            handle(.entrancePicked(nil))
            return
        }
        let frames = env.frames
        Task { [weak self] in
            var pick: EntrancePick?
            if let jpeg = await Self.uprightJPEG(frames) {
                pick = try? await gemini.pickEntrance(still: jpeg)
            }
            if var p = pick, let b = frames.streamBCalibration {
                p.clock = Self.clock(portraitX: p.x, b)
                p.cartCorralClock = p.cartCorralX.map { Self.clock(portraitX: $0, b) }
                pick = p
            }
            self?.handle(.entrancePicked(pick))
        }
    }

    private func lookupProduct(_ words: String) {
        let lookup = env.lookup
        let catalog = env.catalog
        Task { [weak self] in
            var goal: Goal?
            if let hit = (try? await lookup.search(words))?.first {
                goal = Self.goal(for: hit, words: words, catalog: catalog)
            }
            self?.handle(.productLookedUp(goal))             // nil = nothing found (also on errors)
        }
    }

    /// First hit (Canada/US first) → aisle via its category tags; no aisle → word search with the category names.
    /// Goal fields come from the user's words; a brand counts only if they said it.
    static func goal(for hit: OnlineProduct, words: String, catalog: Catalog) -> Goal {
        let said = normalizeText(words)
        let brand = hit.info.brand.flatMap { b -> String? in
            let n = normalizeText(b)
            return !n.isEmpty && " \(said) ".contains(" \(n) ") ? b : nil
        }
        if let aisle = catalog.aisle(forOffTags: hit.categoryTags) {
            return Goal(brand: brand, product: words, category: aisle)
        }
        let names = hit.categoryTags.suffix(4).reversed().compactMap { tag -> String? in
            let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 1 || parts[0] == "en" else { return nil }
            let name = (parts.last ?? "").replacingOccurrences(of: "-", with: " ")
            return name.isEmpty || normalizeText(name) == said ? nil : name
        }
        return Goal(brand: brand, product: words, signWords: Array(names))
    }

    private func describeSurroundings() {
        let perception = env.perception
        Self.background(.userInitiated) { [weak self] in
            let text = perception.describeSurroundings()     // blocking Vision pass: never on main
            Self.onMain { self?.handle(.surroundings(text)) }
        }
    }

    // MARK: - Helpers

    private func publish() {
        let st = session.state
        var overlays = ""
        if st.askPending { overlays += " · ask pending" }
        if let p = st.pause { overlays += " · paused (\(p))" }
        let place = st.placeOverride.map { "\($0) (manual)" } ?? st.place.map { "\($0)" } ?? "unknown"
        let conf = st.placeConfidence.map { String(format: "%.2f", $0) } ?? "–"
        let placeLine = "place \(place) · confidence \(conf) · scene \(st.placeScene.isEmpty ? "–" : st.placeScene)"
            + " · asked \(st.placeTries)×"
        notes.update(step: st.step, overlays: overlays, place: placeLine, goal: st.goal, queue: st.queue, found: foundGoals.count, listening: st.isListening)
        if st.isListening != lastListening {
            lastListening = st.isListening
            onListeningChange?(st.isListening)
        }
        if let last = lastUpdate, last.step == st.step, last.line == st.lastLine, last.walking == st.isWalking { return }
        lastUpdate = (st.step, st.lastLine, st.isWalking)
        onUpdate?(st.step, st.lastLine, st.isWalking)
    }

    /// Feedback drops narration at the brief level; keep it in step with the session ("quieter" / setup).
    private func syncVerbosity() {
        let v = session.state.verbosity
        guard v != feedbackVerbosity else { return }
        feedbackVerbosity = v
        env.feedback.verbosity = v
    }

    /// Full-res 0.5× still → upright JPEG (~2000 px, 0.8), encoded off the main thread. nil without a camera.
    private static func uprightJPEG(_ frames: FrameSource) async -> Data? {
        guard let still = try? await frames.captureStill() else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: NetworkJPEG.encode(still)) }
        }
    }

    /// Clock position of an upright-still x from the live Stream B intrinsics (same sensor, normalized x).
    static func clock(portraitX x: Double, _ b: CaptureCalibration.StreamB) -> Int {
        clockPosition(portraitX: x, intrinsics: CameraGeometry.mat3(b.intrinsics), sensorHeight: Double(b.height))
    }

    private static func waitWhileSpeaking(_ feedback: FeedbackOutput, maxSeconds: Double) async {
        await waitWhile(maxSeconds: maxSeconds) { feedback.isSpeaking }
    }

    private static func waitWhile(maxSeconds: Double, _ condition: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + maxSeconds
        while condition(), ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Runs `work` on a global queue (services are thread-safe; their types aren't marked Sendable).
    private nonisolated static func background(_ qos: DispatchQoS.QoSClass, _ work: @escaping () -> Void) {
        nonisolated(unsafe) let work = work
        DispatchQueue.global(qos: qos).async { work() }
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    /// Brand and product names for on-device recognition (§9 `contextualStrings`).
    private static func recognitionHints(_ catalog: Catalog) -> [String] {
        var hints: [String] = []
        for p in catalog.extraProducts {
            if let b = p.brand { hints.append(b) }
            hints.append(p.name)
        }
        hints += catalog.aisles.keys.sorted().map { $0.replacingOccurrences(of: "_", with: " ") }
        return hints
    }

    /// Safety + Perception values in the overlay's shape.
    nonisolated static func snapshot(safety s: SafetyDebugSnapshot, perception p: PerceptionDebugSnapshot) -> UIDebugSnapshot {
        var u = UIDebugSnapshot()
        if s.source != .idle {
            u.corridorNearest = s.corridorDistance
            u.corridorPoints = s.source == .lidar ? s.corridorPoints : nil
            u.closingSpeed = s.closingSpeed
            u.timeToContact = s.timeToContact.map(Double.init)
            u.steer = s.steer
        }
        u.stairs = s.stairs ?? s.lastStairsAnnounced
        u.detections = p.detections
        if let b = p.trackedBox {                            // Gemini item finder box, drawn like a detection
            u.detections.append(Detection(label: "Gemini target", confidence: p.trackConfidence, box: b))
        }
        u.textBoxes = p.textRegions.map { UIDebugTextBox(text: $0.text, box: $0.box) }
        u.handPoint = p.pointedSpot ?? p.handTip
        u.notes = s.lines + [
            "perception \(p.mode.rawValue) · model \(p.modelLoaded ? "loaded" : "missing")"
                + String(format: " · YOLO %.1f fps · Vision %.1f fps", p.yoloFPS, p.visionFPS),
            "last event \(p.lastEvent.isEmpty ? "–" : p.lastEvent)",
        ]
        return u
    }
}

/// Session values for the debug overlay, readable from any thread.
private final class SessionRunnerNotes: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []

    var lines: [String] { lock.withLock { value } }

    func update(step: Step, overlays: String, place: String, goal: Goal?, queue: [Goal], found: Int, listening: Bool) {
        var out = ["phase \(step.title)" + overlays + (listening ? " · listening" : ""), place]
        out.append("goal \(goal.map(Self.describe) ?? "–") · queue \(queue.isEmpty ? "–" : queue.map(Self.describe).joined(separator: ", "))")
        out.append("found \(found)")
        lock.withLock { value = out }
    }

    private static func describe(_ g: Goal) -> String {
        [g.brand, g.product].compactMap { $0 }.joined(separator: " ") + (g.category.map { " [\($0)]" } ?? "")
    }
}
