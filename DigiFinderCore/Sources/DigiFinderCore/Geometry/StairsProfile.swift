// Stairs floor profile (§5.4). Spoken only, never vibrates.

/// `floorY`: learned floor height in the leveled frame (negative, below the phone).
public func detectStairs(_ pts: [Vec3], floorY: Float) -> StairsObservation? {
    var bins = [Int: [Float]]()
    for p in pts where abs(p.x) < 0.4 && p.y < -0.4 && p.z > 0.3 && p.z < 5 { bins[Int(p.z / 0.1), default: []].append(p.y) }
    let profile = bins.keys.sorted().compactMap { k -> (z: Float, h: Float)? in
        guard let ys = bins[k], ys.count >= 8 else { return nil }
        return (Float(k) * 0.1, ys.sorted()[ys.count / 2] - floorY)
    }
    guard let first = profile.first(where: { abs($0.h) > 0.13 }) else { return nil }
    if first.h > 0 {
        let rises = zip(profile, profile.dropFirst()).filter { $1.h - $0.h > 0.13 && $1.h - $0.h < 0.22 }.count
        guard rises >= 2, let top = profile.map(\.h).max() else { return nil }
        let more = profile.last.map { $0.z > 4.5 && $0.h >= top - 0.05 } ?? false
        return StairsObservation(up: true, distance: first.z, steps: Int((top / 0.18).rounded()), more: more)
    } else {
        let drop = -(profile.map(\.h).min() ?? first.h)
        return StairsObservation(up: false, distance: first.z, steps: drop > 0.3 ? Int((drop / 0.18).rounded()) : nil, more: false)
    }
}
