// Danger corridor and emergency rule (§5.3).

/// Waist-to-head box ahead of the user, in leveled meters.
public struct Corridor {
    public var halfWidth: Float = 0.4, below: Float = 0.4, above: Float = 0.6, maxForward: Float = 3
    /// Points closer than this are ignored (0.2 m normally; ~0.7 m in shelf mode: the user's hand, the held item).
    public var minForward: Float = 0.2

    public init(halfWidth: Float = 0.4, below: Float = 0.4, above: Float = 0.6, maxForward: Float = 3, minForward: Float = 0.2) {
        self.halfWidth = halfWidth; self.below = below; self.above = above; self.maxForward = maxForward
        self.minForward = minForward
    }

    /// Shelf mode (§5.3): anything closer than ~0.7 m never alerts.
    public static let shelf = Corridor(minForward: 0.7)

    public func contains(_ p: Vec3) -> Bool {
        abs(p.x) < halfWidth && p.y > -below && p.y < above && p.z > minForward && p.z < maxForward
    }
}

/// 5th-percentile forward distance of leveled points inside the corridor; nil if fewer than 40 points.
public func nearestInCorridor(_ pts: [Vec3], c: Corridor = .init()) -> Float? {
    corridorObstacle(pts, c: c)?.distance
}

/// The nearest thing in the corridor: where it is and the points that make it up.
public struct GeometryObstacle: Equatable {
    /// 5th-percentile forward distance (m).
    public var distance: Float
    /// Median lateral offset of the near points (m, + right): feeds `steerDirection(obstacleX:)`.
    public var x: Float
    /// Corridor points within 0.3 m behind `distance` (at most 200, evenly sampled): project them into Stream B to
    /// find the YOLO box that labels the obstacle.
    public var points: [Vec3]
    /// All corridor points this frame.
    public var corridorCount: Int

    public init(distance: Float, x: Float, points: [Vec3] = [], corridorCount: Int = 0) {
        self.distance = distance; self.x = x; self.points = points; self.corridorCount = corridorCount
    }
}

public func corridorObstacle(_ pts: [Vec3], c: Corridor = .init(), minPoints: Int = 40) -> GeometryObstacle? {
    let inside = pts.filter(c.contains)
    guard inside.count >= max(minPoints, 1) else { return nil }
    let zs = inside.map(\.z).sorted()
    let nearest = zs[zs.count / 20]
    var near = inside.filter { $0.z <= nearest + 0.3 }
    let xs = near.map(\.x).sorted()
    let x = xs.isEmpty ? 0 : xs[xs.count / 2]
    if near.count > 200 {
        let step = Double(near.count) / 200
        near = (0..<200).map { near[Int(Double($0) * step)] }
    }
    return GeometryObstacle(distance: nearest, x: x, points: near, corridorCount: inside.count)
}

/// `h`: nearest-distance history over ~0.5 s, oldest first. Callers require 2 consecutive true frames
/// (or use `GeometryDangerRule`, which does). Closing speed is the least-squares slope of the history.
/// Emergency: distance < 1.0 m and closing > 0.2 m/s, or TTC < 1.5 s with distance < 3 m.
/// Never while rotating > 1.5 rad/s (lanyard swing); never when not closing (stationary rule).
public func isEmergency(_ h: [(t: Double, d: Float)], rotationRate: Double) -> Bool {
    isEmergency(h, rotationRate: rotationRate, shelfMode: false)
}

/// Shelf mode (§5.3): only things moving toward the user alert (TTC < 1.5 s), and nothing closer than ~0.7 m.
public func isEmergency(_ h: [(t: Double, d: Float)], rotationRate: Double, shelfMode: Bool) -> Bool {
    guard rotationRate.isFinite, abs(rotationRate) < 1.5,
          let l = h.last, l.d.isFinite, let closing = closingSpeed(h) else { return false }
    guard closing > 0.2 else { return false }                  // stationary rule
    let ttc = l.d / closing
    if shelfMode { return l.d >= Corridor.shelf.minForward && ttc < 1.5 }
    return l.d < 1.0 || (ttc < 1.5 && l.d < 3)
}
