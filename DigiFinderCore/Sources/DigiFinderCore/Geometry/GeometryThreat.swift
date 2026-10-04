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
    /// Owner decision: 1.5 m (2.5 m fired too far away).
    public static let overheadMaxDistance: Float = 1.5
    /// Standing or sitting still: nothing closer than this alerts (table, chair, own hands).
    public static let stillMinDistance: Float = 0.8
}

/// Alert sensitivity by place (owner decision). Store: sensitive. General (school, campus, office, home): calm —
/// people must be clearly coming at the user on a collision course, and a crowd only alerts for an imminent hit.
public struct ThreatProfile: Equatable {
    public var name: String
    /// Things this close to the walking line count (m, half width).
    public var inPathHalfWidth: Float
    /// Own approach speed (beyond the user's walking) that makes a mover a threat (m/s): known movers / anything else.
    public var approachMinMover: Float
    public var approachMinOther: Float
    /// Movers alert within this time to contact (s) and distance (m).
    public var approachTTC: Float
    public var approachMaxDistance: Float
    /// Frames in a row before an alert, and the same-obstacle cooldown (s).
    public var consecutiveFrames: Int
    public var cooldown: Double
    /// Judge "in path" by where the obstacle will be at contact (its sideways motion), not where it is now:
    /// someone crossing in front only counts if their path meets the user's.
    public var collisionCourse: Bool
    /// Many people in view → only an imminent collision (`crowdTTC`) alerts.
    public var crowdDamping: Bool
    public var crowdPeople: Int
    public var crowdTTC: Float

    public init(name: String, inPathHalfWidth: Float, approachMinMover: Float, approachMinOther: Float, approachTTC: Float,
                approachMaxDistance: Float, consecutiveFrames: Int, cooldown: Double, collisionCourse: Bool,
                crowdDamping: Bool, crowdPeople: Int = 4, crowdTTC: Float = 1.0) {
        self.name = name; self.inPathHalfWidth = inPathHalfWidth; self.approachMinMover = approachMinMover
        self.approachMinOther = approachMinOther; self.approachTTC = approachTTC
        self.approachMaxDistance = approachMaxDistance; self.consecutiveFrames = consecutiveFrames
        self.cooldown = cooldown; self.collisionCourse = collisionCourse; self.crowdDamping = crowdDamping
        self.crowdPeople = crowdPeople; self.crowdTTC = crowdTTC
    }

    /// Grocery store: sensitive (the original thresholds).
    public static let store = ThreatProfile(name: "store", inPathHalfWidth: 0.35, approachMinMover: 0.4, approachMinOther: 0.8,
                                            approachTTC: 2.5, approachMaxDistance: 2.7, consecutiveFrames: 3, cooldown: 5,
                                            collisionCourse: false, crowdDamping: false)
    /// Anywhere else: calm. Verify on device (§10) in a busy hallway.
    public static let general = ThreatProfile(name: "general", inPathHalfWidth: 0.25, approachMinMover: 0.8,
                                              approachMinOther: 1.2, approachTTC: 1.5, approachMaxDistance: 2.7,
                                              consecutiveFrames: 5, cooldown: 10, collisionCourse: true,
                                              crowdDamping: true, crowdPeople: 4, crowdTTC: 1.0)
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
    /// Sideways speed of the obstacle (m/s, + = moving right), for the collision-course check.
    public var lateralSpeed: Float?
    /// People YOLO sees in the frame (crowd damping).
    public var peopleInView: Int

    public init(distance: Float, x: Float, closing: Float?, walking: Bool, grounded: Bool, label: String? = nil,
                lateralSpeed: Float? = nil, peopleInView: Int = 0) {
        self.distance = distance; self.x = x; self.closing = closing; self.walking = walking
        self.grounded = grounded; self.label = label; self.lateralSpeed = lateralSpeed; self.peopleInView = peopleInView
    }

    /// The label names something that moves on its own.
    public var isMover: Bool {
        guard let l = label?.lowercased(), !l.isEmpty else { return false }
        return ThreatTuning.movers.contains { l.contains($0) }
    }
}

/// The threat and a short reason (for the debug overlay and tuning).
public func assessThreat(_ i: ThreatInput, profile p: ThreatProfile = .store) -> (kind: ThreatKind, reason: String) {
    guard i.distance.isFinite, i.distance > 0 else { return (.none, "no distance") }
    let closing = i.closing ?? 0
    let ttc = closing > 0 ? i.distance / closing : .infinity
    if p.collisionCourse, let vx = i.lateralSpeed, ttc.isFinite {
        // Where it will be when it reaches the user: crossing in front only counts if the paths meet.
        let atContact = i.x + vx * ttc
        guard abs(atContact) <= p.inPathHalfWidth, abs(i.x) <= 1.0 else { return (.none, "not on a collision course") }
    } else {
        guard abs(i.x) <= p.inPathHalfWidth else { return (.none, "off to the side") }
    }
    let ownApproach = closing - (i.walking ? ThreatTuning.walkingSpeed : 0)
    let approachMin = i.isMover ? p.approachMinMover : p.approachMinOther

    if !i.walking && i.distance < ThreatTuning.stillMinDistance { return (.none, "still: within reach") }

    let crowded = p.crowdDamping && i.peopleInView >= p.crowdPeople
    let ttcLimit = crowded ? min(p.crowdTTC, p.approachTTC) : p.approachTTC
    if ownApproach >= approachMin && ttc < ttcLimit && i.distance <= p.approachMaxDistance {
        return (.approaching, crowded ? "crowd: imminent collision" : "moving toward user")
    }
    if crowded && ownApproach >= approachMin && ttc < p.approachTTC { return (.none, "crowd: not imminent") }
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

/// Demo (owner decision): a table in the path while walking gets the full alert (one vibration + steer), once per
/// table approach. Normal tabletops (~0.75 m) sit below the danger corridor, so this looks lower, only for tables.
public struct TableAlertRule {
    /// Owner decision: buzz once when a table in the path is 0.8 m away while walking ("Table ahead, steer to N").
    public static let alertDistance: Float = 0.8
    /// Tracked from this far, so a tabletop that drops below the camera's view right before 0.8 m still alerts.
    public static let trackDistance: Float = 1.5
    /// Last seen this close, centered, and gone within `vanishWindow` s while still walking → it's at the user's
    /// waist, below the view (a chest lanyard loses a tabletop at ~0.8–1 m).
    public static let vanishDistance: Float = 1.1
    public static let vanishHalfWidth: Float = 0.25
    public static let vanishWindow: Double = 1.0
    public static let halfWidth: Float = 0.35
    public static let frames = 2
    /// One buzz per table: re-armed only after no table within `trackDistance` for this long.
    public static let rearmAfter: Double = 3

    private var streak = 0
    private var armed = true
    private var lastNear: (t: Double, distance: Float, x: Float)?

    public init() {}

    /// YOLO (OIV7) table classes. Exact names: "Vegetable", "Tablet computer", "Tableware" are not tables.
    public static let labels: Set<String> = ["Table", "Coffee table", "Kitchen & dining room table", "Desk", "Billiard table"]
    public static func isTable(_ label: String?) -> Bool { label.map(labels.contains) ?? false }

    /// Corridor reaching down to ~0.55 m above the floor (floor ~1.3 m below a chest lanyard when unknown).
    public static func corridor(floorY: Float?) -> Corridor {
        Corridor(below: floorY.map { min(0.8, max(0.4, -$0 - 0.55)) } ?? 0.75, maxForward: trackDistance + 0.5)
    }

    /// One frame. True when this frame should alert. Standing still or turning fast: never (and no tracking).
    public mutating func update(t: Double, walking: Bool, rotating: Bool, obstacle: GeometryObstacle?,
                                label: String?) -> Bool {
        guard walking, !rotating else {
            streak = 0
            lastNear = nil
            return false
        }
        let table = obstacle.flatMap { o in
            Self.isTable(label) && o.distance <= Self.trackDistance && abs(o.x) <= Self.halfWidth ? o : nil
        }
        if let o = table {
            lastNear = (t, o.distance, o.x)
        } else if let n = lastNear, t - n.t >= Self.rearmAfter || t < n.t {
            lastNear = nil
            armed = true
        }
        guard armed else { return false }
        if let o = table, o.distance <= Self.alertDistance {
            streak += 1
        } else {
            streak = 0
            // Was right ahead and close, now out of view while walking on: it's below the camera.
            if table == nil, let n = lastNear, t - n.t <= Self.vanishWindow, n.distance <= Self.vanishDistance,
               abs(n.x) <= Self.vanishHalfWidth {
                armed = false
                return true
            }
            return false
        }
        guard streak >= Self.frames else { return false }
        armed = false
        streak = 0
        return true
    }

    /// Stream stopped.
    public mutating func reset() {
        streak = 0
        lastNear = nil
        armed = true
    }

    /// Where it was last seen (for the steer line when it vanished below the view).
    public var lastSeen: GeometryObstacle? { lastNear.map { GeometryObstacle(distance: $0.distance, x: $0.x) } }
}

/// Fences and barricades (owner decision; YOLO has no class for them): while walking, something across the path at
/// waist height with open space above it. Walls and shelves fill the space above, so they don't count. Same alert as
/// tables: one vibration + "Barrier ahead, steer to N o'clock", once per approach.
public struct BarrierAlertRule {
    /// Owner decision: buzz from ~2.7 m.
    public static let maxDistance: Float = 2.7
    public static let minDistance: Float = 0.3
    /// Path width checked, as 10 cm columns across ±0.35 m.
    public static let halfWidth: Float = 0.35
    public static let columns = 7
    /// Columns that must be blocked, and how far apart (front to back) their nearest points may be: a line across.
    public static let minBlocked = 4
    public static let maxDepthSpread: Float = 0.5
    public static let minColumnPoints = 2
    /// Barrier band: 0.3 m above the floor up to 0.2 m below the phone (a ~1–1.2 m fence on a chest lanyard).
    public static let bandFromFloor: Float = 0.3
    public static let bandTop: Float = -0.2
    /// Above band (phone to head height) must be nearly empty near the barrier.
    public static let aboveBottom: Float = 0.05
    public static let aboveTop: Float = 0.6
    /// Above-band points allowed: this many, or a quarter of the barrier's own points (LiDAR noise, a sign on top).
    public static let maxAbovePoints = 40
    public static let frames = 3
    public static let cooldown: Double = 20

    private var streak = 0
    private var lastAlert = -Double.infinity

    public init() {}

    /// The barrier in this frame's points, or nil. `points` are its near points (for the YOLO label check).
    public static func find(_ pts: [Vec3], floorY: Float?) -> GeometryObstacle? { check(pts, floorY: floorY).barrier }

    /// The barrier, or nil and why not (debug overlay: "barrier: 3/7 columns", "barrier: 120 pts above (wall?)").
    public static func check(_ pts: [Vec3], floorY: Float?) -> (barrier: GeometryObstacle?, reason: String) {
        let floor = floorY ?? -1.3
        let low = floor + bandFromFloor
        var nearest = [Float](repeating: .infinity, count: columns)
        var counts = [Int](repeating: 0, count: columns)
        var band: [Vec3] = []
        for p in pts where abs(p.x) < halfWidth && p.y > low && p.y < bandTop
            && p.z > minDistance && p.z < maxDistance + maxDepthSpread {
            let c = min(columns - 1, max(0, Int((p.x + halfWidth) / (2 * halfWidth) * Float(columns))))
            counts[c] += 1
            nearest[c] = min(nearest[c], p.z)
            band.append(p)
        }
        let blocked = (0..<columns).filter { counts[$0] >= minColumnPoints && nearest[$0] <= maxDistance }
            .map { nearest[$0] }.sorted()
        guard blocked.count >= minBlocked else { return (nil, "\(blocked.count)/\(columns) columns blocked") }
        guard let first = blocked.first, let last = blocked.last, last - first <= maxDepthSpread else {
            return (nil, String(format: "not a line across (%.1f m deep)", (blocked.last ?? 0) - (blocked.first ?? 0)))
        }
        let distance = blocked[blocked.count / 2]
        let above = pts.filter { abs($0.x) < halfWidth + 0.05 && $0.y > aboveBottom && $0.y < aboveTop
            && $0.z > minDistance && $0.z < distance + 0.6 }.count
        guard above < max(maxAbovePoints, band.count / 4) else { return (nil, "\(above) pts above (wall?)") }
        let near = band.filter { $0.z <= distance + 0.3 }
        let x = near.isEmpty ? 0 : near.map(\.x).reduce(0, +) / Float(near.count)
        return (GeometryObstacle(distance: distance, x: x, points: Array(near.prefix(200)), corridorCount: band.count),
                String(format: "FOUND %.1f m (%d/%d columns, %d above)", distance, blocked.count, columns, above))
    }

    /// One frame. True when this frame should alert. nil (or not walking) restarts the streak.
    public mutating func update(t: Double, walking: Bool, rotating: Bool, barrier: GeometryObstacle?) -> Bool {
        guard walking, !rotating, barrier != nil else {
            streak = 0
            return false
        }
        streak += 1
        guard streak >= Self.frames else { return false }
        if t >= lastAlert && t - lastAlert < Self.cooldown { return false }
        lastAlert = t
        streak = 0
        return true
    }

    public mutating func reset() { streak = 0 }
}
