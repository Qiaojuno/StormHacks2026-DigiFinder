// End of an aisle from LiDAR (§5.2 InAisle): the shelves stop on both sides. Safety runs the tracker on every
// depth frame (it doesn't know the task phase) and sends `SessionEvent.aisleEnd`; the session uses it only in
// InAisle after ≥ 5 steps. Thresholds: verify on device (§10).

/// Where shelf-like surfaces are looked for, in leveled meters from the phone (+x right, +y up, +z forward).
public enum AisleEndTuning {
    /// Lateral band on each side: past the user's body, within a typical aisle half-width.
    public static let lateralMin: Float = 0.35
    public static let lateralMax: Float = 1.6
    /// Forward band (the depth camera only sees the sides from ~1 m ahead).
    public static let forwardMin: Float = 0.8
    public static let forwardMax: Float = 3.5
    /// Height band: above the floor (a chest lanyard is ~1.3 m up) up to above head height.
    public static let heightMin: Float = -1.0
    public static let heightMax: Float = 0.5
    /// Points a side needs to count as a shelf.
    public static let minPoints = 40
    /// Shelves on both sides this long (s) = between shelves.
    public static let shelvesHold = 1.0
    /// Then open on both sides this long (s), while walking = the end of the aisle.
    public static let openHold = 0.6
}

public struct AisleSides: Equatable {
    public var left: Bool
    public var right: Bool
    public init(left: Bool, right: Bool) { self.left = left; self.right = right }
}

/// Whether a shelf-like surface stands on each side.
public func aisleSides(_ pts: [Vec3]) -> AisleSides {
    var l = 0, r = 0
    let t = AisleEndTuning.self
    for p in pts where p.z >= t.forwardMin && p.z <= t.forwardMax && p.y >= t.heightMin && p.y <= t.heightMax {
        let a = abs(p.x)
        guard a >= t.lateralMin && a <= t.lateralMax else { continue }
        if p.x < 0 { l += 1 } else { r += 1 }
    }
    return AisleSides(left: l >= t.minPoints, right: r >= t.minPoints)
}

/// Between shelves (both sides, held) → open on both sides (held, while walking) fires once.
public struct AisleEndTracker: Equatable {
    public private(set) var betweenShelves = false
    private var bothSince: Double?
    private var openSince: Double?

    public init() {}

    /// True once when the shelves stop on both sides after the user walked between them.
    public mutating func update(t: Double, sides: AisleSides, walking: Bool) -> Bool {
        if sides.left && sides.right {
            openSince = nil
            let since = bothSince ?? t
            bothSince = since
            if t - since >= AisleEndTuning.shelvesHold { betweenShelves = true }
            return false
        }
        bothSince = nil
        guard betweenShelves, !sides.left, !sides.right, walking else {
            openSince = nil
            return false
        }
        let since = openSince ?? t
        openSince = since
        guard t - since >= AisleEndTuning.openHold else { return false }
        betweenShelves = false
        openSince = nil
        return true
    }

    public mutating func reset() { self = AisleEndTracker() }
}
