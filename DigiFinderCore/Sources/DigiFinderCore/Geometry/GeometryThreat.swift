// Threat level (§5.3). Proximity alone never alerts: the app supplements the cane, so it looks at what the object
// is and how it moves, and only buzzes for a high threat.
//
// - High (`approaching`, vibrate + speak): something moving toward the user on its own — a person walking at them,
//   a rolling shopping cart. Its own approach speed (closing speed minus the user's walking) must be real and
//   contact close. Known movers (people, carts, strollers…) need less evidence than an unlabeled shape.
// - Low (`overhead`, spoken only, no vibration): something at chest or head height that doesn't reach the floor
//   (open cabinet door, sign, shelf edge) while the user walks toward it — the cane passes under it.
// - None: walls, shelves, tables, boxes, things off to the side, and anything near a user standing or sitting still.

public enum ThreatKind: Equatable {
    case none
    /// Moving toward the user.
    case approaching
    /// Above cane height, in the walking path.
    case overhead
}

public enum ThreatTuning {
    /// Only things this close to the walking line count (m, half width). The corridor is wider, for steering.
    public static let inPathHalfWidth: Float = 0.35
    /// Nominal walking speed subtracted from the closing speed while walking (m/s). Verify on device (§10).
    public static let walkingSpeed: Float = 1.0
    /// The object's own speed toward the user that makes it a mover (m/s): known movers / anything else.
    public static let approachMinMover: Float = 0.4
    public static let approachMinOther: Float = 0.8
    /// YOLO (OIV7) labels of things that move on their own; matched lowercased, by containment.
    public static let movers = ["person", "man", "woman", "boy", "girl", "cart", "wheelchair", "bicycle", "dog", "car"]
    /// Movers alert within this time to contact (s) and distance (m).
    public static let approachTTC: Float = 2.5
    public static let approachMaxDistance: Float = 4
    /// Overhead obstacles alert within this time to contact (s) and distance (m), only while walking.
    public static let overheadTTC: Float = 2.0
    public static let overheadMaxDistance: Float = 2.5
    /// Standing or sitting still: nothing closer than this alerts (table, chair, own hands).
    public static let stillMinDistance: Float = 0.8
}

public struct ThreatInput: Equatable {
    /// Meters ahead and lateral offset (+ right) of the obstacle.
    public var distance: Float
    public var x: Float
    /// Closing speed (m/s, + = getting nearer: the user's walking plus the object's own motion).
    public var closing: Float?
    public var walking: Bool
    /// The obstacle reaches down below the waist band at its distance (the cane will touch it).
    public var grounded: Bool
    /// YOLO label of the obstacle, if any ("Person", "Cart").
    public var label: String?

    public init(distance: Float, x: Float, closing: Float?, walking: Bool, grounded: Bool, label: String? = nil) {
        self.distance = distance; self.x = x; self.closing = closing; self.walking = walking
        self.grounded = grounded; self.label = label
    }

    /// The label names something that moves on its own.
    public var isMover: Bool {
        guard let l = label?.lowercased(), !l.isEmpty else { return false }
        return ThreatTuning.movers.contains { l.contains($0) }
    }
}

/// The threat and a short reason (for the debug overlay and tuning).
public func assessThreat(_ i: ThreatInput) -> (kind: ThreatKind, reason: String) {
    guard i.distance.isFinite, i.distance > 0 else { return (.none, "no distance") }
    guard abs(i.x) <= ThreatTuning.inPathHalfWidth else { return (.none, "off to the side") }
    let closing = i.closing ?? 0
    let ttc = closing > 0 ? i.distance / closing : .infinity
    let ownApproach = closing - (i.walking ? ThreatTuning.walkingSpeed : 0)
    let approachMin = i.isMover ? ThreatTuning.approachMinMover : ThreatTuning.approachMinOther

    if !i.walking && i.distance < ThreatTuning.stillMinDistance { return (.none, "still: within reach") }

    if ownApproach >= approachMin && ttc < ThreatTuning.approachTTC && i.distance <= ThreatTuning.approachMaxDistance {
        return (.approaching, "moving toward user")
    }
    if i.walking && !i.grounded && ttc < ThreatTuning.overheadTTC && i.distance <= ThreatTuning.overheadMaxDistance {
        return (.overhead, "above cane height")
    }
    return (.none, i.walking ? "cane can find it" : "standing still, nothing approaching")
}

/// Whether the obstacle reaches below the waist band (≥ `minPoints` points between the floor and the band, near it).
/// `floorY` nil: assume the floor ~1.3 m below a chest lanyard.
public func isGrounded(_ pts: [Vec3], obstacle o: GeometryObstacle, floorY: Float?, corridor c: Corridor = .init(),
                       minPoints: Int = 15) -> Bool {
    let floor = floorY ?? -1.3
    var n = 0
    for p in pts where abs(p.x - o.x) < 0.3 && abs(p.z - o.distance) < 0.4 && p.y > floor + 0.1 && p.y <= -c.below {
        n += 1
        if n >= minPoints { return true }
    }
    return false
}
