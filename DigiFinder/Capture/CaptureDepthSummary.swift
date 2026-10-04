import AVFoundation
import Foundation

/// A cheap digest of one depth frame for the debug overlay (~2 Hz).
struct CaptureDepthSummary: Equatable {
    /// Sample time (host clock seconds).
    var time: Double
    var width: Int
    var height: Int
    /// Share of sampled pixels with a usable depth, 0...1.
    var validFraction: Float
    /// Robust minimum (2nd percentile) of usable depths, meters.
    var nearest: Float?
    /// Median depth in the central box (the middle of the portrait image), meters.
    var center: Float?
    var isFiltered: Bool
    /// False if the depth is only relative (not metric).
    var isAbsolute: Bool

    var line: String {
        func m(_ v: Float?) -> String { v.map { String(format: "%.2f m", $0) } ?? "–" }
        return "depth \(width)×\(height) valid \(Int(validFraction * 100))% near \(m(nearest)) center \(m(center))"
            + (isAbsolute ? "" : " (relative)")
    }

    /// `depth` must be Float32 (see `CaptureDepthMap.float32`).
    static func make(from depth: AVDepthData, time: Double) -> CaptureDepthSummary? {
        CaptureDepthMap.read(depth) { map in
            let step = max(1, map.width / 80)
            var all: [Float] = []
            var central: [Float] = []
            var sampled = 0
            let cu = map.width / 2, cv = map.height / 2, bu = max(1, map.width / 10), bv = max(1, map.height / 10)
            var v = step / 2
            while v < map.height {
                var u = step / 2
                while u < map.width {
                    sampled += 1
                    if let z = map.depth(u, v) {
                        all.append(z)
                        if abs(u - cu) <= bu && abs(v - cv) <= bv { central.append(z) }
                    }
                    u += step
                }
                v += step
            }
            all.sort(); central.sort()
            return CaptureDepthSummary(
                time: time, width: map.width, height: map.height,
                validFraction: sampled > 0 ? Float(all.count) / Float(sampled) : 0,
                nearest: all.isEmpty ? nil : all[all.count / 50],
                center: central.isEmpty ? nil : central[central.count / 2],
                isFiltered: depth.isDepthDataFiltered,
                isAbsolute: depth.depthDataAccuracy == .absolute)
        }
    }
}
