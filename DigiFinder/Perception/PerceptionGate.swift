import Foundation

/// Admits work at most `fps` times per second (≤ 0 pauses). Used with a busy flag: drop while busy.
struct PerceptionGate {
    private var last = -Double.infinity

    mutating func admit(_ t: Double, fps: Double) -> Bool {
        guard fps > 0 else { return false }
        guard t - last >= 0.9 / fps else { return false }
        last = t
        return true
    }
}
