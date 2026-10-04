import CoreMedia
import Foundation

/// Measured delivery rate (frames per second, smoothed) for the debug overlay.
struct CaptureRateMeter {
    private var last: Double?
    private var smoothed: Double = 0

    mutating func tick(_ t: Double) {
        if let last, t > last {
            let fps = 1 / (t - last)
            smoothed = smoothed == 0 ? fps : smoothed * 0.9 + fps * 0.1
        }
        last = t
    }

    /// Smoothed rate; 0 once no frame has arrived for a second (sample times use the host clock).
    var fps: Double {
        guard let last else { return 0 }
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        return now - last > 1 ? 0 : smoothed
    }
}
