// Danger corridor and emergency rule (§5.3).

public struct Corridor {
    public var halfWidth: Float = 0.4, below: Float = 0.4, above: Float = 0.6, maxForward: Float = 3

    public init(halfWidth: Float = 0.4, below: Float = 0.4, above: Float = 0.6, maxForward: Float = 3) {
        self.halfWidth = halfWidth; self.below = below; self.above = above; self.maxForward = maxForward
    }
}

/// 5th-percentile forward distance of leveled points inside the corridor; nil if fewer than 40 points.
public func nearestInCorridor(_ pts: [Vec3], c: Corridor = .init()) -> Float? {
    let z = pts.filter { abs($0.x) < c.halfWidth && $0.y > -c.below && $0.y < c.above && $0.z > 0.2 && $0.z < c.maxForward }
               .map(\.z).sorted()
    guard z.count >= 40 else { return nil }
    return z[z.count / 20]
}

/// `h`: nearest-distance history over ~0.5 s, oldest first. Callers require 2 consecutive true frames.
public func isEmergency(_ h: [(t: Double, d: Float)], rotationRate: Double) -> Bool {
    guard rotationRate < 1.5, let f = h.first, let l = h.last, l.t > f.t else { return false }
    let closing = (f.d - l.d) / Float(l.t - f.t)
    guard closing > 0.2 else { return false }                  // stationary rule
    return l.d < 1.0 || (l.d / closing < 1.5 && l.d < 3)
}
