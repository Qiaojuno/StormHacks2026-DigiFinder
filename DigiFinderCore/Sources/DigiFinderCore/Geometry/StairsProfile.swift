// Stairs floor profile (§5.4). Spoken only, never vibrates.

/// Tunables (§10: "Stairs rise/run ranges" are verified on device).
public struct GeometryStairsParams: Equatable {
    public var riseMin: Float = 0.13, riseMax: Float = 0.22
    public var runMin: Float = 0.22, runMax: Float = 0.35
    /// Slack on the run range for 10 cm binning.
    public var runTolerance: Float = 0.1
    public var stepHeight: Float = 0.18
    public var binSize: Float = 0.1
    public var minPointsPerBin = 8
    /// Bins within this height band form one tread / floor plateau.
    public var flatTolerance: Float = 0.06
    /// Owner report (random things called stairs): a staircase needs this many matching rises (was 2).
    public var minRises = 3
    /// Lateral strip the profile reads (m, + right).
    public var xMin: Float = -0.4, xMax: Float = 0.4

    public init(riseMin: Float = 0.13, riseMax: Float = 0.22, runMin: Float = 0.22, runMax: Float = 0.35,
                runTolerance: Float = 0.1, stepHeight: Float = 0.18, binSize: Float = 0.1, minPointsPerBin: Int = 8,
                flatTolerance: Float = 0.06) {
        self.riseMin = riseMin; self.riseMax = riseMax; self.runMin = runMin; self.runMax = runMax
        self.runTolerance = runTolerance; self.stepHeight = stepHeight; self.binSize = binSize
        self.minPointsPerBin = minPointsPerBin; self.flatTolerance = flatTolerance
    }
}

/// `floorY`: learned floor height in the leveled frame (negative, below the phone).
public func detectStairs(_ pts: [Vec3], floorY: Float) -> StairsObservation? {
    detectStairs(pts, floorY: floorY, params: GeometryStairsParams())
}

/// Floor profile ahead (|x| < 0.4, below the waist band, z 0.3–5 m), median height per bin relative to the floor,
/// grouped into flat plateaus (floor, treads). Bins straddling a riser are dropped.
/// Up: ≥ 2 consecutive rises of 0.13–0.22 m, ~0.22–0.35 m apart; count = visible rise ÷ 0.18 ("more" if the top
/// isn't visible). Down: a sharp floor edge onto a visible surface ≥ 0.13 m lower (steps only when lower steps
/// are visible).
public func detectStairs(_ pts: [Vec3], floorY: Float, params p: GeometryStairsParams) -> StairsObservation? {
    guard floorY.isFinite, p.binSize > 0 else { return nil }
    var bins = [Int: [Float]]()
    for q in pts where q.x > p.xMin && q.x < p.xMax && q.y < -0.4 && q.z > 0.3 && q.z < 5 && q.y.isFinite {
        bins[Int(q.z / p.binSize), default: []].append(q.y)
    }
    let profile = bins.keys.sorted().compactMap { k -> StairsBin? in
        guard let ys = bins[k], ys.count >= p.minPointsPerBin else { return nil }
        return StairsBin(k: k, h: ys.sorted()[ys.count / 2] - floorY)
    }
    var plateaus = stairsPlateaus(profile, p)
    guard !plateaus.isEmpty else { return nil }

    // Floor reference: the first plateau if it's at floor level, else a virtual floor ending where the profile starts.
    if abs(plateaus[0].h) > p.flatTolerance {
        plateaus.insert(StairsPlateau(startK: plateaus[0].startK - 2, endK: plateaus[0].startK - 1, h: 0, bins: 0), at: 0)
    }
    let floor = plateaus[0]
    let floorEnd = Float(floor.endK + 1) * p.binSize

    // Missing points beyond the floor are not stairs: shiny store floors and the grazing angle from a chest lanyard
    // often return nothing past ~2 m. A drop needs a visible lower surface (below).
    guard plateaus.count > 1 else { return nil }
    let next = plateaus[1]
    if next.h - floor.h >= p.riseMin {
        // Up: consecutive valid rises from the floor.
        var rises = 0
        var lastIndex = 0
        var lastRiseZ: Float?
        for i in 1..<plateaus.count {
            let rise = plateaus[i].h - plateaus[i - 1].h
            let z = Float(plateaus[i].startK) * p.binSize
            let spacingOK = lastRiseZ.map { z - $0 >= p.runMin - p.runTolerance && z - $0 <= p.runMax + p.runTolerance } ?? true
            guard rise >= p.riseMin, rise <= p.riseMax, spacingOK else { break }
            rises += 1; lastIndex = i; lastRiseZ = z
        }
        guard rises >= p.minRises else { return nil }
        let top = plateaus[lastIndex].h
        let last = plateaus[lastIndex]
        // The top isn't visible when the profile ends on a tread (not a landing) near the range limit, or when the
        // next step would sit above the waist band that the profile ignores.
        // Only riser remnants (single bins at or above the top) may follow the last counted tread.
        let trailing = plateaus.suffix(from: lastIndex + 1)
        let endsAtTop = trailing.allSatisfy { $0.bins <= 1 && $0.h >= top - 0.01 }
        let profileEnd = Float((plateaus.last?.endK ?? last.endK) + 1) * p.binSize
        let lastLength = Float(last.endK - last.startK + 1) * p.binSize
        let nextHidden = top + p.stepHeight + floorY >= -0.42
        let endsOnTread = lastLength <= p.runMax + p.runTolerance
        let more = endsAtTop && (profileEnd >= 4.5 || (nextHidden && endsOnTread))
        let steps = max(Int((top / p.stepHeight).rounded()), rises)
        return StairsObservation(up: true, distance: floorEnd, steps: steps, more: more)
    }
    // Down: a sharp edge (the lower surface starts right after the floor, not a gradual slope from a leaning phone),
    // a floor run of at least ~0.5 m before it, and a lower surface seen in at least 3 bins.
    if next.h - floor.h <= -p.riseMin, next.startK - floor.endK <= 3, floor.bins >= 5, next.bins >= 3 {
        let lowest = plateaus.dropFirst().map(\.h).min() ?? next.h
        let drop = floor.h - lowest
        let steps: Int? = drop >= 0.3 ? Int((drop / p.stepHeight).rounded()) : nil
        return StairsObservation(up: false, distance: floorEnd, steps: steps, more: false)
    }
    return nil
}

/// Stricter check (owner report: random things were called stairs). Up-stairs must show the same steps on the left
/// and right halves of the path (shelves, boxes, a cart base rarely do) at about the same distance. Returns the
/// observation or why not (debug overlay).
public func detectStairsStrict(_ pts: [Vec3], floorY: Float) -> (obs: StairsObservation?, reason: String) {
    guard let full = detectStairs(pts, floorY: floorY) else { return (nil, "no steps") }
    guard full.up else { return (full, "edge down") }
    var half = GeometryStairsParams()
    half.minPointsPerBin = 4
    half.xMin = -0.4; half.xMax = 0
    let left = detectStairs(pts, floorY: floorY, params: half)
    half.xMin = 0; half.xMax = 0.4
    let right = detectStairs(pts, floorY: floorY, params: half)
    guard let l = left, let r = right, l.up, r.up else { return (nil, "one side only (shelf?)") }
    guard abs(l.distance - full.distance) <= 0.4, abs(r.distance - full.distance) <= 0.4 else {
        return (nil, "sides don't line up")
    }
    return (full, String(format: "steps up %.1f m", full.distance))
}

struct StairsBin { var k: Int; var h: Float }
struct StairsPlateau { var startK: Int; var endK: Int; var h: Float; var bins: Int }

/// Groups bins into flat plateaus, drops single-bin plateaus that sit between their neighbours (riser bins),
/// then merges neighbours at the same height.
func stairsPlateaus(_ profile: [StairsBin], _ p: GeometryStairsParams) -> [StairsPlateau] {
    var groups: [[StairsBin]] = []
    for b in profile {
        if var g = groups.last, let last = g.last, b.k - last.k <= 2 {
            let hs = g.map(\.h) + [b.h]
            if (hs.max() ?? 0) - (hs.min() ?? 0) <= p.flatTolerance {
                g.append(b); groups[groups.count - 1] = g; continue
            }
        }
        groups.append([b])
    }
    func plateau(_ g: [StairsBin]) -> StairsPlateau {
        let hs = g.map(\.h).sorted()
        return StairsPlateau(startK: g[0].k, endK: g[g.count - 1].k, h: hs[hs.count / 2], bins: g.count)
    }
    var ps = groups.map(plateau)
    var i = 1
    while i < ps.count - 1 {
        let a = ps[i - 1].h, b = ps[i].h, c = ps[i + 1].h
        if ps[i].bins == 1 && ((a + 0.03 < b && b < c - 0.03) || (a - 0.03 > b && b > c + 0.03)) {
            ps.remove(at: i)
        } else {
            i += 1
        }
    }
    var merged: [StairsPlateau] = []
    for q in ps {
        if var m = merged.last, abs(m.h - q.h) <= p.flatTolerance, q.startK - m.endK <= 2 {
            m.h = (m.h * Float(m.bins) + q.h * Float(q.bins)) / Float(max(m.bins + q.bins, 1))
            m.endK = q.endK; m.bins += q.bins
            merged[merged.count - 1] = m
        } else {
            merged.append(q)
        }
    }
    return merged
}

// MARK: - Floor height

/// Floor height (leveled y, negative) from points 0.6–2 m ahead, well below the chest; nil when the patch
/// isn't flat (stairs, clutter) or too sparse.
public func estimateFloorY(_ pts: [Vec3]) -> Float? {
    let ys = pts.filter { abs($0.x) < 0.6 && $0.z > 0.6 && $0.z < 2.0 && $0.y < -0.6 && $0.y.isFinite }.map(\.y).sorted()
    guard ys.count >= 30 else { return nil }
    guard ys[ys.count * 2 / 5] - ys[ys.count / 10] <= 0.05 else { return nil }
    return ys[ys.count / 4]
}

/// Smoothed floor height across frames.
public struct GeometryFloorTracker {
    public var smoothing: Float
    public private(set) var floorY: Float?

    public init(initial: Float? = nil, smoothing: Float = 0.2) { floorY = initial; self.smoothing = smoothing }

    @discardableResult
    public mutating func update(_ pts: [Vec3]) -> Float? {
        guard let f = estimateFloorY(pts) else { return floorY }
        floorY = floorY.map { $0 + (f - $0) * smoothing } ?? f
        return floorY
    }
}

// MARK: - Confirmation and announcements

public enum GeometryStairsAnnouncement: Equatable {
    /// "Stairs going up, about 8 steps, 3 meters, 12 o'clock."
    case first(StairsObservation)
    /// "Stairs, 1 meter ahead."
    case near(StairsObservation)
}

/// Confirm, announce once per staircase, then once more at ~1 m (from LiDAR, or counted down with the pedometer once
/// the near floor is out of view). Owner report (false stairs): seen for `confirmSeconds` (YOLO "Stairs" agreeing:
/// `yoloConfirmSeconds`) with the distance not growing (the user walks toward it); gaps up to `maxGap` are allowed.
public struct GeometryStairsTracker {
    public var confirmSeconds: Double = 1.0
    public var yoloConfirmSeconds: Double = 0.4
    public var maxGap: Double = 0.3
    /// The distance may grow at most this much while confirming (LiDAR noise).
    public var distanceSlack: Float = 0.2
    public var nearDistance: Float
    /// Seconds without stairs before the next detection counts as a new staircase.
    public var forgetAfter: Double
    public var stepLength: Float
    public private(set) var current: StairsObservation?
    private var since: (t: Double, distance: Float)?
    private var lastSeen: Double?
    private var announcedFirst = false
    private var announcedNear = false

    public init(nearDistance: Float = 1.2, forgetAfter: Double = 5, stepLength: Float = 0.7) {
        self.nearDistance = nearDistance
        self.forgetAfter = forgetAfter; self.stepLength = stepLength
    }

    public mutating func update(_ obs: StairsObservation?, yoloStairs: Bool, t: Double) -> GeometryStairsAnnouncement? {
        if let seen = lastSeen, t - seen > forgetAfter { reset() }
        guard let o = obs else {
            if let seen = lastSeen, t - seen > maxGap { since = nil }
            return nil
        }
        if let c = current, announcedFirst, c.up != o.up { reset() }
        if let s = since, let seen = lastSeen, t - seen > maxGap || t < s.t { since = nil }
        let start = since ?? (t, o.distance)
        since = start
        lastSeen = t
        current = o
        if !announcedFirst {
            guard o.distance <= start.distance + distanceSlack else {     // moving away / shifting: not stairs
                since = (t, o.distance)
                return nil
            }
            guard t - start.t >= (yoloStairs ? yoloConfirmSeconds : confirmSeconds) else { return nil }
            announcedFirst = true
            if o.distance <= nearDistance { announcedNear = true }
            return .first(o)
        }
        if !announcedNear && o.distance <= nearDistance {
            announcedNear = true
            return .near(o)
        }
        return nil
    }

    /// Pedometer countdown from the last LiDAR distance (~0.7 m per step).
    public mutating func walked(steps: Int, t: Double) -> GeometryStairsAnnouncement? {
        guard steps > 0, announcedFirst, !announcedNear, var c = current else { return nil }
        c.distance = max(c.distance - Float(steps) * stepLength, 0)
        current = c
        lastSeen = t
        guard c.distance <= nearDistance else { return nil }
        announcedNear = true
        return .near(c)
    }

    public mutating func reset() {
        current = nil; since = nil; lastSeen = nil; announcedFirst = false; announcedNear = false
    }
}

/// "Stairs going up, about 8 steps, 3 meters, 12 o'clock." / "Stairs going down, 2 meters, 12 o'clock."
public func stairsAnnouncement(_ o: StairsObservation, clock: Int = 12) -> String {
    var parts = ["Stairs going \(o.up ? "up" : "down")"]
    if let n = o.steps, n > 0 { parts.append(o.more ? "more than \(n) steps" : "about \(n) step\(n == 1 ? "" : "s")") }
    parts.append(spokenMeters(o.distance))
    parts.append(clockPhrase(clock))
    return parts.joined(separator: ", ") + "."
}

/// "Stairs, 1 meter ahead."
public func stairsNearAnnouncement() -> String { "Stairs, 1 meter ahead." }

/// Whole meters, at least 1: "1 meter", "3 meters".
public func spokenMeters(_ d: Float) -> String {
    let m = d.isFinite ? max(1, Int(d.rounded())) : 1
    return "\(m) meter\(m == 1 ? "" : "s")"
}
