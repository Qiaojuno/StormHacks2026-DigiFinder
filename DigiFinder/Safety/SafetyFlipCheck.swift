import AVFoundation
import Foundation
import DigiFinderCore

/// "Phone may be flipped around." (§5.8): depth almost all closer than 0.2 m (lens against the body) for about a
/// second, at most once per 30 s; the controller runs it only while walking. Thresholds are verified on device (§10).
struct SafetyFlipCheck {
    static let hold: Double = 1
    static let interval: Double = 30
    static let sampleInterval: Double = 0.1
    /// Raw samples per depth-map row.
    static let gridColumns = 40

    private var blockedSince: Double?
    private var lastFired: Double?
    private var lastSample = -Double.infinity

    /// True when the hint should be sent now.
    mutating func update(_ depth: AVDepthData, t: Double) -> Bool {
        guard t - lastSample >= Self.sampleInterval || t < lastSample else { return false }
        lastSample = t
        guard Geometry.depthLooksBlocked(Self.sample(depth)) else {
            blockedSince = nil
            return false
        }
        let since = blockedSince ?? t
        blockedSince = since
        guard t - since >= Self.hold else { return false }
        if let last = lastFired, t - last < Self.interval, t >= last { return false }
        lastFired = t
        return true
    }

    /// Raw depth values on a coarse grid (meters; holes stay 0/NaN so `depthLooksBlocked` skips them).
    /// `CaptureDepthMap.depth` drops values under 0.15 m, which is exactly what this check needs, so read raw.
    static func sample(_ depth: AVDepthData) -> [Float] {
        guard let d = CaptureDepthMap.float32(depth) else { return [] }
        return CaptureDepthMap.read(d) { map -> [Float] in
            let step = max(1, map.width / gridColumns)
            var out: [Float] = []
            out.reserveCapacity((map.width / step + 1) * (map.height / step + 1))
            var v = step / 2
            while v < map.height {
                var u = step / 2
                while u < map.width {
                    out.append(map.raw(u, v))
                    u += step
                }
                v += step
            }
            return out
        } ?? []
    }
}
