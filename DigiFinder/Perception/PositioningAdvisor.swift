import Foundation
import DigiFinderCore

/// Positioning prompts (§5.8), rate-limited. "Phone may be flipped around." is the safety lane's job, not this one.
struct PositioningAdvisor {
    struct Input {
        var mode: PerceptionMode
        var time: Double
        /// Mean luma 0...1 of the frame, nil if unknown.
        var luma: Double?
        /// CoreMotion gravity (device frame, pointing down).
        var gravity: SIMD3<Float>
        /// rad/s
        var rotationRate: Double
        var handVisible: Bool
        var lines: [PerceptionTextRegion]
        var pointedRegion: PerceptionProductRegion?
        /// LiDAR distance straight ahead (meters), nil if unknown.
        var shelfDistance: Float?
    }

    var minInterval = 4.0
    var sameHintInterval = 10.0

    private var since: [String: Double] = [:]
    private var lastAny = -Double.infinity
    private var lastByHint: [String: Double] = [:]

    mutating func reset() { since = [:] }

    mutating func advise(_ i: Input) -> PositioningHint? {
        guard i.mode == .signs || i.mode == .pointing else { since = [:]; return nil }
        let t = i.time
        var candidates: [PositioningHint] = []
        func held(_ name: String, _ condition: Bool, for duration: Double) -> Bool {
            guard condition else { since[name] = nil; return false }
            let s = since[name] ?? t
            since[name] = s
            return t - s >= duration
        }

        if held("dark", (i.luma ?? 1) < 0.08, for: 1.0) { candidates.append(.tooDark) }
        if held("fast", i.rotationRate > 1.2, for: 0.5) { candidates.append(.slowDown) }
        let g = i.gravity, gl = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
        let pitchDown = gl > 0.1 ? Double(asin(min(max(-g.z / gl, -1), 1))) * 180 / .pi : 0
        if held("floor", pitchDown > 35, for: 1.5) { candidates.append(.tiltUp) }
        if held("ceiling", pitchDown < -30, for: 1.5) { candidates.append(.tiltDown) }

        if i.mode == .pointing {
            if held("nohand", !i.handVisible, for: 3.0) { candidates.append(.pointInFront) }
            let tooNear = (i.shelfDistance.map { $0 > 0 && $0 < 0.3 } ?? false)
            let clipped = i.pointedRegion.map { $0.box.x < 0.01 || $0.box.maxX > 0.99 } ?? false
            if held("near", tooNear || clipped, for: 1.0) { candidates.append(.stepBack) }
            let heights = i.lines.map(\.box.height).sorted()
            let small = !heights.isEmpty && heights[heights.count / 2] < 0.012
            if held("small", i.handVisible && i.pointedRegion == nil && small, for: 1.5) { candidates.append(.moveCloser) }
        }

        guard t - lastAny >= minInterval else { return nil }
        for hint in candidates {
            let key = "\(hint)"
            if t - (lastByHint[key] ?? -Double.infinity) >= sameHintInterval {
                lastAny = t
                lastByHint[key] = t
                return hint
            }
        }
        return nil
    }
}
