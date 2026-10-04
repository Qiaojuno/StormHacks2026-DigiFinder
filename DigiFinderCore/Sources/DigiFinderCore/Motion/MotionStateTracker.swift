// Motion state (layer 1): Walking / Standing from the pedometer and the accelerometer, with hysteresis.
// One source for everyone: the app's DeviceMotionService runs this tracker, Safety reads `isWalking`, and the
// session gets the same value through `SessionEvent.motion(walking:)`. Task phases read it; they never set it.
//
// Rule over a 1.5 s window: a movement signal (steps in the window and the user-acceleration spread).
// Clearly below the low threshold → Standing; clearly above the high threshold → Walking; in between → keep the
// previous state; sensor unavailable or no fresh data → keep the previous state.

public enum MotionState: Equatable { case standing, walking }

/// Thresholds for `MotionStateTracker`. Verify on device (§10): lanyard swing, slow shuffling at the shelf.
public enum MotionTuning {
    /// Window the movement signal is computed over (s).
    public static let window = 1.5
    /// User-acceleration spread (standard deviation, g) at or below which the phone is clearly still → Standing.
    /// Verify on device.
    public static let standingAccelStd = 0.02
    /// Spread at or above which the user is clearly moving → Walking. Verify on device.
    public static let walkingAccelStd = 0.06
    /// Pedometer steps in the window that count as walking (when the phone isn't clearly still). Verify on device.
    public static let walkingSteps = 2
    /// Fewer acceleration samples in the window than this = no accelerometer signal (unavailable or dropped out).
    public static let minAccelSamples = 15
    /// The newest acceleration sample must be at most this old (s), else the sensor dropped out.
    public static let maxSampleAge = 0.5
}

/// The movement signal over the window.
public struct MotionMovement: Equatable {
    /// User-acceleration standard deviation (g); nil without enough fresh samples.
    public var accelStd: Double?
    /// Pedometer steps in the window.
    public var steps: Int

    public init(accelStd: Double?, steps: Int) { self.accelStd = accelStd; self.steps = steps }
}

/// Pure hysteresis rule; feed it samples with a monotonic clock in seconds.
public struct MotionStateTracker: Equatable {
    public private(set) var state: MotionState
    private var accel: [Sample] = []
    private var stepTimes: [Double] = []
    private var lastTotal: Int?

    private struct Sample: Equatable { var t: Double; var g: Double }

    public init(initial: MotionState = .standing) { state = initial }

    /// Magnitude of the user acceleration (g) at time `t`.
    public mutating func addAcceleration(t: Double, magnitude: Double) {
        guard magnitude.isFinite else { return }
        accel.append(Sample(t: t, g: magnitude))
        trim(now: t)
    }

    /// Cumulative pedometer count at time `t`; the increase counts as steps at `t`.
    public mutating func addSteps(t: Double, total: Int) {
        defer { lastTotal = total }
        guard let last = lastTotal, total > last else { return }
        stepTimes += Array(repeating: t, count: min(total - last, 20))
        trim(now: t)
    }

    /// The movement signal at `now`.
    public func movement(at now: Double) -> MotionMovement {
        let w = MotionTuning.window
        let recent = accel.filter { now - $0.t <= w && $0.t <= now + 1e-9 }
        var std: Double?
        if recent.count >= MotionTuning.minAccelSamples, let newest = recent.last, now - newest.t <= MotionTuning.maxSampleAge {
            let mean = recent.map(\.g).reduce(0, +) / Double(recent.count)
            let v = recent.map { ($0.g - mean) * ($0.g - mean) }.reduce(0, +) / Double(recent.count)
            std = v.squareRoot()
        }
        let steps = stepTimes.filter { now - $0 <= w && $0 <= now + 1e-9 }.count
        return MotionMovement(accelStd: std, steps: steps)
    }

    /// Applies the hysteresis rule at `now` and returns the (possibly unchanged) state.
    @discardableResult
    public mutating func update(now: Double) -> MotionState {
        trim(now: now)
        if let next = Self.decide(movement(at: now)) { state = next }
        return state
    }

    /// nil = in between or no data: keep the previous state.
    public static func decide(_ m: MotionMovement) -> MotionState? {
        if let a = m.accelStd {
            if a <= MotionTuning.standingAccelStd { return .standing }    // phone clearly still (stale step batches lose)
            if a >= MotionTuning.walkingAccelStd { return .walking }
        }
        if m.steps >= MotionTuning.walkingSteps { return .walking }
        return nil
    }

    private mutating func trim(now: Double) {
        let keep = MotionTuning.window + 1
        if let i = accel.firstIndex(where: { now - $0.t <= keep }), i > 0 { accel.removeFirst(i) }
        else if let last = accel.last, now - last.t > keep { accel.removeAll() }
        stepTimes.removeAll { now - $0 > keep }
    }
}
