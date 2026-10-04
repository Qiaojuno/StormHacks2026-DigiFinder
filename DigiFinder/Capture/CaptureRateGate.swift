import Foundation

/// Drops frames above a target rate (per stream, on that stream's queue; the owner provides locking).
struct CaptureRateGate {
    private var interval: Double = 0
    private var nextDue = -Double.infinity

    /// ≤ 0 pauses delivery.
    mutating func setMaxFPS(_ fps: Double) {
        interval = fps > 0 ? 1 / fps : .infinity
        nextDue = -.infinity
    }

    /// True if a frame at `t` (seconds) may pass. A small tolerance absorbs timestamp jitter.
    mutating func admit(_ t: Double) -> Bool {
        guard interval.isFinite else { return false }
        guard t >= nextDue - 0.005 else { return false }
        nextDue = max(nextDue + interval, t + interval * 0.5)
        return true
    }
}
