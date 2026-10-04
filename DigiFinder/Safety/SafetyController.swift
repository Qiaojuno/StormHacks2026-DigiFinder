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
/// Events: `.danger(cutRecording:)`, `.dangerCleared`, `.stairs(_)` (first sighting, then the ~1 m update),
/// `.positioning(.phoneFlipped)`.
final class SafetyController: SafetyService, SafetyDebugSource, @unchecked Sendable {
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
    private let calibration: CaptureCalibration?

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
    private var flip = SafetyFlipCheck()
    private var lastDepthUptime = -Double.infinity
    private var lastDebugLabelTime = -Double.infinity
    private var debugLabel = SafetyLabeler.Result(label: SafetyLabeler.fallbackLabel, box: nil, points: [])
    private var fallbackStreak = 0

    private let queue = DispatchQueue(label: "DigiFinder.safety", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private enum Action {
        case danger(label: String, steer: Steer)
        case pulse
        case event(SessionEvent)
    }

    init(frames: FrameSource, depth: DepthProvider, motion: MotionService, detector: ObjectDetector,
         feedback: FeedbackOutput, voice: VoiceInput) {
        self.frames = frames; self.depth = depth; self.motion = motion
        self.detector = detector; self.feedback = feedback; self.voice = voice
        calibration = SafetyStreamBLens.calibration(of: frames)
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

    // MARK: SafetyDebugSource

    var debugSnapshot: SafetyDebugSnapshot { config.withLock { snapshot } }

    // MARK: LiDAR path (capture queue)

    private func handle(_ f: DepthFrame) {
        let begin = DispatchTime.now().uptimeNanoseconds
        let shelfMode = config.withLock { work.shelfMode }
        let gravity = motion.gravity
        let rotation = motion.rotationRate
        let walking = motion.isWalking
        let steps = motion.steps
        let t = f.time.isValid && f.time.seconds.isFinite ? f.time.seconds : ProcessInfo.processInfo.systemUptime

        var snap = SafetyDebugSnapshot(source: .lidar, time: t, shelfMode: shelfMode, rotationRate: rotation)
        let actions: [Action] = lane.withLock {
            lastDepthUptime = ProcessInfo.processInfo.systemUptime
            var out: [Action] = []
            let pts = depth.points(f, gravity: gravity)
            let basis = CameraGeometry.levelBasis(gravity: gravity)

            // Danger first: it's the only part with a latency budget.
            let r = danger.evaluate(pts, t: t, rotationRate: rotation, walking: walking, shelfMode: shelfMode)
            if let o = r.obstacle, r.emergency || t - lastDebugLabelTime >= Self.debugLabelInterval || t < lastDebugLabelTime {
                lastDebugLabelTime = t
                debugLabel = SafetyLabeler.label(points: o.points, basis: basis,
                                                 lens: SafetyStreamBLens.make(calibration: calibration, depth: f.depth),
                                                 detections: detector.latest)
            }
            if r.emergency, let o = r.obstacle, policy.wantsAlert(label: debugLabel.label, x: o.x, t: t) {
                policy.didAlert(label: debugLabel.label, x: o.x, t: t)
                out.append(.danger(label: debugLabel.label, steer: r.steer))
                snap.lastAlert = alertPhrase(label: debugLabel.label, steer: r.steer)
            }
            switch policy.update(t: t, emergency: r.emergency, distance: r.obstacle?.distance, closing: r.closingSpeed) {
            case .pulse: out.append(.pulse)
            case .cleared: out.append(.event(.dangerCleared))
            case .none: break
            }

            // Stairs (spoken by the session; never vibrates).
            if let s = stairs.process(pts, t: t, steps: steps, rotationRate: rotation, detections: detector.latest) {
                out.append(.event(.stairs(s)))
                snap.lastStairsAnnounced = s
            }

            // Phone flipped (not in shelf mode).
            if flip.update(f.depth, t: t, shelfMode: shelfMode) {
                out.append(.event(.positioning(.phoneFlipped)))
            }

            snap.corridorDistance = r.obstacle?.distance
            snap.corridorPoints = r.obstacle?.corridorCount ?? 0
            snap.obstacleX = r.obstacle?.x
            snap.closingSpeed = r.closingSpeed
            snap.timeToContact = r.timeToContact
            snap.steer = r.steer
            snap.emergency = r.emergency
            if r.obstacle != nil {
                snap.label = debugLabel.label
                snap.labelBox = debugLabel.box
                snap.obstaclePoints = debugLabel.points
            }
            snap.alertActive = policy.isActive
            snap.floorY = stairs.floorY
            snap.stairs = stairs.latest
            snap.stairsProfile = stairs.profile
            return out
        }
        let latency = perform(actions, frameTime: t)
        snap.processingMs = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
        store(snap, alertLatency: latency)
    }

    // MARK: Fallback path (safety queue, no depth frames)

    private func fallbackTick() {
        let now = ProcessInfo.processInfo.systemUptime
        let shelfMode = config.withLock { work.shelfMode }
        let rotation = motion.rotationRate
        var snap = SafetyDebugSnapshot(source: .fallback, time: now, shelfMode: shelfMode, rotationRate: rotation)
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
            if emergency, let th = threat {
                let label = SafetyLabeler.spokenName(th.label)
                let x = Float(th.box.midX - 0.5)
                if policy.wantsAlert(label: label, x: x, t: now) {
                    policy.didAlert(label: label, x: x, t: now)
                    out.append(.danger(label: label, steer: .unknown))
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
            case let .danger(label, steer):
                let cut = voice.isListening
                feedback.danger(label, steer: steer)
                if let ft = frameTime { latency = (CMClockGetTime(CMClockGetHostTimeClock()).seconds - ft) * 1000 }
                voice.cancel()
                emit(.danger(cutRecording: cut))
            case .pulse:
                (feedback as? SafetyPulseOutput)?.dangerPulse()
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
