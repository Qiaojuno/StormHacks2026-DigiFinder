// Closing speed and time to contact over a distance history (§5.3 step 5), plus the 2-frame emergency rule.

/// Closing speed (m/s, positive = getting closer): least-squares slope of distance over time, negated.
/// nil with fewer than 2 finite samples or less than 50 ms of history.
public func closingSpeed(_ h: [(t: Double, d: Float)]) -> Float? {
    let s = h.filter { $0.t.isFinite && $0.d.isFinite }
    guard s.count >= 2, let first = s.first, let last = s.last, last.t - first.t >= 0.05 else { return nil }
    let n = Double(s.count)
    let mt = s.reduce(0) { $0 + $1.t } / n
    let md = s.reduce(0) { $0 + Double($1.d) } / n
    var num = 0.0, den = 0.0
    for p in s { num += (p.t - mt) * (Double(p.d) - md); den += (p.t - mt) * (p.t - mt) }
    guard den > 0 else { return nil }
    return Float(-num / den)
}

/// Seconds until contact at the current closing speed; nil when not closing.
public func timeToContact(distance: Float, closingSpeed v: Float) -> Float? {
    guard distance.isFinite, v.isFinite, v > 1e-3, distance >= 0 else { return nil }
    return distance / v
}

/// Rolling window of nearest-obstacle distances.
public struct GeometryDistanceHistory {
    public var window: Double
    /// A frame-to-frame jump larger than this (m, plus 4 m/s × the frame gap) means a different object:
    /// the history restarts.
    public var jumpReset: Float
    public private(set) var samples: [(t: Double, d: Float)] = []

    public init(window: Double = 0.5, jumpReset: Float = 0.5) {
        self.window = window; self.jumpReset = jumpReset
    }

    /// Adds a sample; `distance` nil (nothing in the corridor) clears the history.
    public mutating func add(t: Double, distance: Float?) {
        guard let d = distance, d.isFinite, t.isFinite else { samples.removeAll(); return }
        if let last = samples.last, t < last.t || abs(d - last.d) > jumpReset + 4 * Float(t - last.t) { samples.removeAll() }
        samples.append((t, d))
        samples.removeAll { t - $0.t > window }
    }

    public mutating func reset() { samples.removeAll() }

    public var latest: Float? { samples.last?.d }
    public var closingSpeed: Float? { DigiFinderCore.closingSpeed(samples) }
    public var timeToContact: Float? {
        guard let d = latest, let v = closingSpeed else { return nil }
        return DigiFinderCore.timeToContact(distance: d, closingSpeed: v)
    }
}

/// Emergency rule with the 2-consecutive-frame requirement (§5.3). Feed every depth frame.
public struct GeometryDangerRule {
    public var consecutiveFrames: Int
    public private(set) var history: GeometryDistanceHistory
    public private(set) var streak = 0

    public init(consecutiveFrames: Int = 2, window: Double = 0.5) {
        self.consecutiveFrames = max(consecutiveFrames, 1)
        history = GeometryDistanceHistory(window: window)
    }

    /// `distance`: this frame's corridor nearest (nil = nothing there). In shelf mode, distances under ~0.7 m are
    /// ignored and only approaching objects (TTC < 1.5 s) count. Returns true while the emergency holds for the
    /// required number of consecutive frames (the caller applies its own alert cooldown).
    public mutating func update(t: Double, distance: Float?, rotationRate: Double, shelfMode: Bool = false) -> Bool {
        var d = distance
        if shelfMode, let v = d, v < Corridor.shelf.minForward { d = nil }
        history.add(t: t, distance: d)
        if isEmergency(history.samples, rotationRate: rotationRate, shelfMode: shelfMode) {
            streak += 1
        } else {
            streak = 0
        }
        return streak >= consecutiveFrames
    }

    public mutating func reset() { history.reset(); streak = 0 }
}
