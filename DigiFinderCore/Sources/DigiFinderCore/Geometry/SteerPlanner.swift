import Foundation

// Steering and the alert line (§5.3): where the nearest walkable gap is, as a clock position.

/// Width of the gap the user needs (half, meters) and how far it must stay open.
public enum SteerTuning {
    public static let gapHalfWidth: Float = 0.35
    /// The gap must be open this far past the obstacle (and at least to `minClear`, at most `maxClear`).
    public static let pastObstacle: Float = 1.0
    public static let minClear: Float = 2.0
    public static let maxClear: Float = 3.0
    /// Scan step and limit (degrees). On a chest lanyard LiDAR sees roughly ±25° ahead; the scan also stays inside
    /// the angles the points actually cover.
    public static let stepDegrees: Double = 5
    public static let maxDegrees: Double = 30
    /// A heading with fewer blocking points than this counts as open (LiDAR noise).
    public static let maxBlockers = 8
    /// Fewer usable points than this: the sides can't be judged.
    public static let minVisible = 30
}

/// Degrees right of straight ahead (negative = left) of the nearest open heading, or nil if no visible heading is
/// open. Headings closest to straight ahead win; on a tie, the side away from the obstacle.
public func openHeading(_ pts: [Vec3], obstacleX: Float, obstacleZ: Float, corridor c: Corridor = .init()) -> Double? {
    scanHeadings(pts, obstacleX: obstacleX, obstacleZ: obstacleZ, corridor: c).open
}

/// The open heading (if any) and the least blocked one (the side with the most room) in the visible field.
func scanHeadings(_ pts: [Vec3], obstacleX: Float, obstacleZ: Float, corridor c: Corridor) -> (open: Double?, leastBlocked: Double?) {
    let band = pts.filter { $0.y > -c.below && $0.y < c.above && $0.z > 0.2 && $0.z.isFinite && $0.x.isFinite }
    guard band.count >= SteerTuning.minVisible else { return (nil, nil) }
    // Field of view actually covered by points (minus a margin so the gap's far edge is still seen).
    var seen = 0.0
    for p in band {
        let deg: Double = abs(atan2(Double(p.x), Double(p.z))) * 180 / Double.pi
        if deg > seen { seen = deg }
    }
    let limit = min(SteerTuning.maxDegrees, seen - 3)
    let need = min(max(obstacleZ + SteerTuning.pastObstacle, SteerTuning.minClear), SteerTuning.maxClear)
    let awaySign: Double = obstacleX > 0 ? -1 : 1            // prefer turning away from the obstacle's side

    func blockers(_ deg: Double) -> Int {
        let r = Float(deg * .pi / 180), s = sin(r), co = cos(r)
        var n = 0
        for p in band {
            let along = p.x * s + p.z * co
            let across = p.x * co - p.z * s
            if abs(across) < SteerTuning.gapHalfWidth && along > 0.2 && along < need { n += 1 }
        }
        return n
    }

    var least: (deg: Double, n: Int)?
    var k = 1.0
    while k * SteerTuning.stepDegrees <= limit {
        let d = k * SteerTuning.stepDegrees
        for deg in [awaySign * d, -awaySign * d] {
            let n = blockers(deg)
            if n < SteerTuning.maxBlockers { return (deg, deg) }
            if least == nil || n < least!.n { least = (deg, n) }
        }
        k += 1
    }
    return (nil, least?.deg)
}

/// Clock position for a steer heading: never 12 (that's where the obstacle is), so a small turn is 1 or 11.
public func steerClock(degreesRight deg: Double) -> Int {
    let h = clockPosition(degreesRight: deg)
    return h == 12 ? (deg >= 0 ? 1 : 11) : h
}

/// `.clock(n)` toward the nearest open gap; `.stop` when every visible heading is blocked; `.unknown` when there
/// aren't enough points to judge.
/// `alwaysClock` (barriers, owner decision): when nothing is fully open, steer toward the side with the most room
/// (usually the barrier's end) instead of "stop. Turn slowly.".
public func steerDirection(_ pts: [Vec3], obstacleX: Float, obstacleZ: Float, corridor c: Corridor = .init(),
                           alwaysClock: Bool = false) -> Steer {
    let visible = pts.lazy.filter { $0.y > -c.below && $0.y < c.above && $0.z > 0.2 && $0.z.isFinite }.count
    guard visible >= SteerTuning.minVisible else { return .unknown }
    let scan = scanHeadings(pts, obstacleX: obstacleX, obstacleZ: obstacleZ, corridor: c)
    if let deg = scan.open { return .clock(steerClock(degreesRight: deg)) }
    if alwaysClock, let deg = scan.leastBlocked { return .clock(steerClock(degreesRight: deg)) }
    return .stop
}

/// "2 meters" / "under 1 meter" / "3 steps" (steps of ~0.7 m).
public func spokenDistance(_ meters: Float, inSteps: Bool = false) -> String {
    if inSteps {
        let n = max(1, Int((meters / 0.7).rounded()))
        return n == 1 ? "1 step" : "\(n) steps"
    }
    if meters < 0.95 { return "under 1 meter" }
    let n = Int(meters.rounded())
    return n == 1 ? "1 meter" : "\(n) meters"
}

/// "Cart ahead, 2 meters, steer to 1 o'clock" / "Person ahead, 1 meter, stop. Turn slowly." / "Obstacle ahead".
/// Blank labels become "Obstacle".
public func alertPhrase(label: String, steer: Steer, distance: Float? = nil, inSteps: Bool = false) -> String {
    let trimmed = label.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    let l = trimmed.isEmpty ? "Obstacle" : trimmed
    var parts = [l.prefix(1).uppercased() + l.dropFirst() + " ahead"]
    if let d = distance, d.isFinite, d > 0 { parts.append(spokenDistance(d, inSteps: inSteps)) }
    switch steer {
    case .clock(let h): parts.append("steer to \(h) o'clock")
    case .stop: return parts.joined(separator: ", ") + ", stop. Turn slowly."
    case .unknown: break
    }
    return parts.joined(separator: ", ")
}

/// "Clear ahead, about 4 meters. Walk straight." / "Clear ahead. Walk straight."
public func clearPathPhrase(meters: Float?, inSteps: Bool = false) -> String {
    guard let m = meters, m.isFinite, m > 0 else { return "Clear ahead. Walk straight." }
    return "Clear ahead, about \(spokenDistance(m, inSteps: inSteps)). Walk straight."
}
