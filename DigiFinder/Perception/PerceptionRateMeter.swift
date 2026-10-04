import Foundation

/// Smoothed frames-per-second of one analysis loop (debug overlay).
struct PerceptionRateMeter {
    private(set) var fps: Double = 0
    private var last: Double?

    mutating func tick(_ t: Double) {
        defer { last = t }
        guard let l = last, t > l else { return }
        let inst = 1 / (t - l)
        fps = fps == 0 ? inst : fps * 0.8 + inst * 0.2
    }
}
