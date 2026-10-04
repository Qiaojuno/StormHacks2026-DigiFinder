// Steer lanes and the alert line (§5.3).

public func steerDirection(_ pts: [Vec3], obstacleX: Float, obstacleZ: Float) -> Steer {
    func lane(_ a: Float, _ b: Float) -> Bool? {
        let z = pts.filter { $0.x > a && $0.x < b && $0.y > -0.4 && $0.y < 0.6 && $0.z > 0.2 && $0.z < 5 }.map(\.z).sorted()
        guard z.count >= 30 else { return nil }
        return z[z.count / 20] > obstacleZ + 0.8
    }
    switch (lane(-0.8, -0.4), lane(0.4, 0.8)) {
    case (true?, true?):   return obstacleX > 0 ? .left : .right
    case (true?, _):       return .left
    case (_, true?):       return .right
    case (false?, false?): return .stop
    default:               return .unknown
    }
}

public func alertPhrase(label: String, steer: Steer) -> String {
    let o = label.prefix(1).uppercased() + label.dropFirst()
    switch steer {
    case .left: return "\(o) ahead, steer left"
    case .right: return "\(o) ahead, steer right"
    case .stop: return "\(o) ahead, stop"
    case .unknown: return "\(o) ahead"
    }
}
