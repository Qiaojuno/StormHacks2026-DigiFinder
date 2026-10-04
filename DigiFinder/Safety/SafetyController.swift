import AVFoundation
import CoreMedia
import Dispatch
import Foundation
import DigiFinderCore

/// Danger + stairs on Stream A (§5.3, §5.4): the safety lane. Runs on the capture queue that delivers depth frames
/// (never the main thread), touches no network, and calls `feedback.danger` itself (depth frame → haptic < 50 ms).
/// Without depth frames (no LiDAR) a timer on the safety queue runs the YOLO box-growth fallback.
///
/// `onEvent` is called on the safety lane (capture or safety queue): hop to the main actor in the handler.
/// Events: `.danger(cutRecording:)`, `.dangerCleared`, `.pathClear`, `.stairs(_)` (first sighting, then the ~1 m
/// update), `.positioning(.phoneFlipped)`, `.aisleEnd`.
///
/// Alerts follow the motion state only (`motion.isWalking`); `StreamWork` (the task phase) never changes them.
final class SafetyController: SafetyService, @unchecked Sendable {
    /// No depth frame for this long → the fallback path takes over (seconds).
    static let depthTimeout: Double = 1
    static let fallbackInterval: Double = 0.1
    /// Fallback emergency: a middle-band box closing within this many seconds…
    static let fallbackTTC: Double = 1.5
    /// …and already this tall in the image (normalized), so far-away growth noise doesn't alert.
    static let fallbackMinHeight = 0.15
    static let maxRotation = 1.5
    /// Debug label refresh while an obstacle is in the corridor (seconds).
    static let debugLabelInterval: Double = 0.5

    private let frames: FrameSource
    private let depth: DepthProvider
    private let motion: MotionService
    private let detector: ObjectDetector
    private let feedback: FeedbackOutput
    private let voice: VoiceInput

    /// Guards `handler`, `work`, `snapshot`, `started` (never held while calling out).
    private let config = NSLock()
    private var handler: ((SessionEvent) -> Void)?
    private var work = StreamWork()
    private var snapshot = SafetyDebugSnapshot()
    private var started = false

    /// Serializes the lane state below between the depth callback and the fallback timer.
    private let lane = NSLock()
    private let danger = DangerDetector()
    private let stairs = StairsDetector()
    private let boxes = SafetyTracker()
    private var policy = SafetyAlertPolicy()
    /// Waiting for the path to open after an alert (lane only).
    private var clearWatch: (since: Double?, until: Double)?
    /// The active alert vibrated (the 2 s repeat pulse only follows a vibrating alert).
    private var alertVibrated = true
    private var flip = SafetyFlipCheck()
    private var aisleEnd = AisleEndTracker()
    private var lastDepthUptime = -Double.infinity
    private var lastDebugLabelTime = -Double.infinity
    private var debugLabel = SafetyLabeler.Result(label: SafetyLabeler.fallbackLabel, box: nil, points: [])
    private var fallbackStreak = 0

    private let queue = DispatchQueue(label: "DigiFinder.safety", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// An obstacle this close to a known up-staircase's distance (m) is its risers, not danger.
    static let stairsDangerMargin: Float = 1.0
    /// After an alert: the way straight ahead must be open this far (m) for `clearHold` s to say "Clear ahead".
    static let clearPathMeters: Float = 2.5
    static let clearPathHold: Double = 0.5
    /// Stop waiting for a clear path this long after the alert (s).
    static let clearPathWatch: Double = 20

    private enum Action {
        case danger(label: String, steer: Steer, distance: Float?, vibrate: Bool)
        case pulse
        case event(SessionEvent)
    }

    init(frames: FrameSource, depth: DepthProvider, motion: MotionService, detector: ObjectDetector,
         feedback: FeedbackOutput, voice: VoiceInput) {
        self.frames = frames; self.depth = depth; self.motion = motion
        self.detector = detector; self.feedback = feedback; self.voice = voice
    }

    deinit { timer?.cancel() }

    // MARK: SafetyService

    var onEvent: ((SessionEvent) -> Void)? {
        get { config.withLock { handler } }
        set { config.withLock { handler = newValue } }
    }

    /// Idempotent. Chains onto `frames.onDepth` (shared with Perception), Safety's work first.
    func start() {
        let first = config.withLock { () -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        let previous = frames.onDepth
        frames.onDepth = { [weak self] f in
            self?.handle(f)
            previous?(f)
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.fallbackInterval, repeating: Self.fallbackInterval, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.fallbackTick() }
        timer = t
        t.resume()
    }

    func setWork(_ w: StreamWork) {
        config.withLock { work = w }
    }

    // MARK: Debug overlay

    var debugSnapshot: SafetyDebugSnapshot { config.withLock { snapshot } }

    // MARK: LiDAR path (capture queue)

    /// The stream (owner decision): when off, no danger or stairs checks run at all.
    private let activeLock = NSLock()
    private var active = true
    private var isActive: Bool { activeLock.lock(); defer { activeLock.unlock() }; return active }

    func setActive(_ on: Bool) {
        activeLock.lock(); active = on; activeLock.unlock()
        if !on { lane.withLock { policy.reset(); danger.reset(); clearWatch = nil } }
    }

    private func handle(_ f: DepthFrame) {
        guard isActive else { return }
        let begin = DispatchTime.now().uptimeNanoseconds
        let gravity = motion.gravity
        let rotation = motion.rotationRate
        let walking = motion.isWalking
        let steps = motion.steps
        let t = f.time.isValid && f.time.seconds.isFinite ? f.time.seconds : ProcessInfo.processInfo.systemUptime

        var snap = SafetyDebugSnapshot(source: .lidar, time: t, walking: walking, rotationRate: rotation)
        // Phase 1, danger only: it's the only part with a latency budget, so its haptics fire before stairs and
        // the flipped check run (§0: depth frame → haptic in < 50 ms).
        var pts: [Vec3] = []
        let dangerActions: [Action] = lane.withLock {
            lastDepthUptime = ProcessInfo.processInfo.systemUptime
            var out: [Action] = []
            pts = depth.points(f, gravity: gravity)
            let basis = CameraGeometry.levelBasis(gravity: gravity)

            // The label feeds the threat level (a person or cart counts sooner than an unknown shape).
            let lens = SafetyStreamBLens.make(streamB: frames.streamBCalibration, depth: f.depth)
            let latest = detector.latest
            var r = danger.evaluate(pts, t: t, rotationRate: rotation, walking: walking,
                                    floorY: stairs.floorY) { o in
                if t - self.lastDebugLabelTime >= Self.debugLabelInterval || t < self.lastDebugLabelTime {
                    self.lastDebugLabelTime = t
                    self.debugLabel = SafetyLabeler.label(points: o.points, basis: basis, lens: lens, detections: latest)
                }
                return self.debugLabel.label == SafetyLabeler.fallbackLabel ? nil : self.debugLabel.label
            }
            // Stairs never vibrate (§5.4): risers of a known up-staircase, or a "Stairs" label, aren't danger.
            if r.emergency, let o = r.obstacle {
                let isStairsLabel = debugLabel.label.lowercased() == "stairs"
                let onKnownStairs = stairs.latest.map { $0.up && abs($0.distance - o.distance) < Self.stairsDangerMargin } ?? false
                if isStairsLabel || onKnownStairs { r.emergency = false }
            }
            if r.emergency, let o = r.obstacle, policy.wantsAlert(label: debugLabel.label, x: o.x, t: t) {
                policy.didAlert(label: debugLabel.label, x: o.x, t: t)
                // Only a high threat (something moving toward the user) vibrates; overhead obstacles are spoken only.
                let vibrate = r.threat == .approaching
                alertVibrated = vibrate
                // Short line, no distance (owner decision): "Person ahead, steer to 1 o'clock".
                out.append(.danger(label: debugLabel.label, steer: r.steer, distance: nil, vibrate: vibrate))
                snap.lastAlert = alertPhrase(label: debugLabel.label, steer: r.steer)
                clearWatch = (since: nil, until: t + Self.clearPathWatch)
            } else if var w = clearWatch {
                // After an alert: once the way straight ahead stays open, say so ("Clear ahead, walk straight").
                let open = !r.emergency && (r.obstacle.map { $0.distance >= Self.clearPathMeters } ?? true)
                if t > w.until {
                    clearWatch = nil
                } else if open {
                    let since = w.since ?? t
                    w.since = since
                    clearWatch = w
                    if t - since >= Self.clearPathHold {
                        out.append(.event(.pathClear(meters: r.obstacle?.distance)))
                        clearWatch = nil
                    }
                } else {
                    w.since = nil
                    clearWatch = w
                }
            }
            switch policy.update(t: t, emergency: r.emergency, distance: r.obstacle?.distance, closing: r.closingSpeed) {
            case .pulse: if alertVibrated { out.append(.pulse) }
            case .cleared: out.append(.event(.dangerCleared))
            case .none: break
            }
            snap.corridorDistance = r.obstacle?.distance
            snap.corridorPoints = r.obstacle?.corridorCount ?? 0
            snap.obstacleX = r.obstacle?.x
            snap.closingSpeed = r.closingSpeed
            snap.timeToContact = r.timeToContact
            snap.steer = r.steer
            snap.emergency = r.emergency
            snap.threatReason = r.reason
            if r.obstacle != nil {
                snap.label = debugLabel.label
                snap.labelBox = debugLabel.box
                snap.obstaclePoints = debugLabel.points
            }
            snap.alertActive = policy.isActive
            return out
        }
        let latency = perform(dangerActions, frameTime: t)

        // Phase 2: stairs and the flipped check, after the haptics.
        let actions: [Action] = lane.withLock {
            var out: [Action] = []
            // Stairs (spoken by the session; never vibrates).
            // Only while walking: sitting at a table or standing still, edges and tables aren't stairs (§5.4).
            if walking, let s = stairs.process(pts, t: t, steps: steps, rotationRate: rotation, detections: detector.latest) {
                out.append(.event(.stairs(s)))
                snap.lastStairsAnnounced = s
            }

            // Phone flipped (walking only).
            if walking, flip.update(f.depth, t: t) {
                out.append(.event(.positioning(.phoneFlipped)))
            }

            // End of an aisle: the shelves stop on both sides (the session decides whether it matters).
            let sides = aisleSides(pts)
            if aisleEnd.update(t: t, sides: sides, walking: walking) { out.append(.event(.aisleEnd)) }
            snap.aisleSides = sides
            snap.betweenShelves = aisleEnd.betweenShelves

            snap.floorY = stairs.floorY
            snap.stairs = stairs.latest
            snap.stairsProfile = stairs.profile
            return out
        }
        _ = perform(actions, frameTime: nil)
        snap.processingMs = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
        store(snap, alertLatency: latency)
    }

    // MARK: Fallback path (safety queue, no depth frames)

    private func fallbackTick() {
        guard isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let rotation = motion.rotationRate
        var snap = SafetyDebugSnapshot(source: .fallback, time: now, walking: motion.isWalking, rotationRate: rotation)
        let actions: [Action]? = lane.withLock {
            guard now - lastDepthUptime > Self.depthTimeout else { return nil }
            var out: [Action] = []
            let (threat, fresh) = boxes.update(detector.latest, t: now)
            let rotating = !rotation.isFinite || abs(rotation) >= Self.maxRotation
            let hit = !rotating && threat.map { $0.ttc < Self.fallbackTTC && $0.box.height >= Self.fallbackMinHeight } == true
            if fresh || !hit { fallbackStreak = hit ? fallbackStreak + 1 : 0 }
            let emergency = fallbackStreak >= 2

            var distance: Float?
            var closing: Float?
            if let th = threat {
                let d = Detection(label: th.label, confidence: 1, box: th.box, trackID: nil)
                distance = (depth as? EstimatedDepthProvider)?.distance(for: d)
                closing = distance.map { $0 / Float(th.ttc) } ?? (th.ttc < 3 ? 1 : 0)
            }
            // No depth to tell overhead from grounded: only things that move on their own (people, carts) alert.
            let mover = threat.map { ThreatInput(distance: 1, x: 0, closing: nil, walking: false, grounded: true,
                                                 label: $0.label).isMover } ?? false
            if emergency, mover, let th = threat {
                let label = SafetyLabeler.spokenName(th.label)
                let x = Float(th.box.midX - 0.5)
                if policy.wantsAlert(label: label, x: x, t: now) {
                    policy.didAlert(label: label, x: x, t: now)
                    out.append(.danger(label: label, steer: .unknown, distance: nil, vibrate: true))
                    snap.lastAlert = alertPhrase(label: label, steer: .unknown)
                }
            }
            switch policy.update(t: now, emergency: emergency, distance: threat == nil ? nil : (distance ?? 1), closing: closing) {
            case .pulse: out.append(.pulse)
            case .cleared: out.append(.event(.dangerCleared))
            case .none: break
            }

            snap.corridorDistance = distance
            snap.obstacleX = threat.map { Float($0.box.midX - 0.5) }
            snap.closingSpeed = closing
            snap.timeToContact = threat.map { Float($0.ttc) }
            snap.emergency = emergency
            snap.label = threat.map { SafetyLabeler.spokenName($0.label) }
            snap.labelBox = threat?.box
            snap.alertActive = policy.isActive
            return out
        }
        guard let actions else { return }
        let latency = perform(actions, frameTime: nil)
        store(snap, alertLatency: latency)
    }

    // MARK: Output

    /// Alert sequence (§9): vibrations first, stop speech, the line (all inside `feedback.danger`), then cancel any
    /// recording and tell the session whether one was cut. Returns frame → haptic latency (ms) when an alert fired.
    private func perform(_ actions: [Action], frameTime: Double?) -> Double? {
        var latency: Double?
        for a in actions {
            switch a {
            case let .danger(label, steer, distance, vibrate):
                let cut = voice.isListening
                feedback.danger(label, steer: steer, distance: distance, vibrate: vibrate)
                if let ft = frameTime { latency = (CMClockGetTime(CMClockGetHostTimeClock()).seconds - ft) * 1000 }
                voice.cancel()
                emit(.danger(cutRecording: cut))
            case .pulse:
                feedback.dangerPulse()
            case let .event(e):
                emit(e)
            }
        }
        return latency
    }

    private func emit(_ e: SessionEvent) {
        let h = config.withLock { handler }
        h?(e)
    }

    private func store(_ s: SafetyDebugSnapshot, alertLatency: Double?) {
        config.withLock {
            var s = s
            let previous = snapshot
            if s.lastAlert == nil { s.lastAlert = previous.lastAlert }
            s.lastAlertLatencyMs = alertLatency ?? previous.lastAlertLatencyMs
            if s.lastStairsAnnounced == nil { s.lastStairsAnnounced = previous.lastStairsAnnounced }
            if s.source == .fallback {
                s.floorY = previous.floorY
                s.stairsProfile = previous.stairsProfile
            }
            snapshot = s
        }
    }
}
