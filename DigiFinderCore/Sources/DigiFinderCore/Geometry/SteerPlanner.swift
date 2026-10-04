// Steer lanes and the alert line (§5.3).

/// Lanes 0.4–0.8 m left and right, same height band as the corridor. A lane is clear when its nearest point
/// (5th percentile) is at least `obstacleZ + 0.8` m away. Points beyond ~5 m still count as seeing the lane
/// (open space), but a lane with fewer than 30 points at any distance is "not visible".
/// Both clear → away from the obstacle side; one → that side; both blocked → stop; not visible → unknown.
public func steerDirection(_ pts: [Vec3], obstacleX: Float, obstacleZ: Float, corridor c: Corridor = .init()) -> Steer {
    func lane(_ a: Float, _ b: Float) -> Bool? {
        let z = pts.filter { $0.x > a && $0.x < b && $0.y > -c.below && $0.y < c.above && $0.z > 0.2 && $0.z.isFinite }
            .map(\.z).sorted()
        guard z.count >= 30 else { return nil }
        return z[z.count / 20] >= obstacleZ + 0.8
    }
    let inner = c.halfWidth, outer = c.halfWidth + 0.4
    switch (lane(-outer, -inner), lane(inner, outer)) {
    case (true?, true?):   return obstacleX > 0 ? .left : .right
    case (true?, _):       return .left
    case (_, true?):       return .right
    case (false?, false?): return .stop
    default:               return .unknown
    }
}

/// "Cart ahead, steer left" / "Person ahead, stop" / "Obstacle ahead". Blank labels become "Obstacle".
public func alertPhrase(label: String, steer: Steer) -> String {
    let trimmed = label.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    let l = trimmed.isEmpty ? "Obstacle" : trimmed
    let o = l.prefix(1).uppercased() + l.dropFirst()
    switch steer {
    case .left: return "\(o) ahead, steer left"
    case .right: return "\(o) ahead, steer right"
    case .stop: return "\(o) ahead, stop"
    case .unknown: return "\(o) ahead"
    }
}
