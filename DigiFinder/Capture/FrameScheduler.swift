import Foundation
import DigiFinderCore

/// Per-stream rate limiting ("own serial queue, drop while busy", §3.6). Thread-safe.
/// Thermal hook: `rateScale` / `setThermalLevel` lowers every rate admitted here. Keep danger work off throttled
/// keys (danger is throttled last, §5.16).
final class FrameScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var lastRun: [String: Double] = [:]
    private var busy = Set<String>()
    private var scale: Double = 1

    init() {}

    /// Multiplies every requested rate (1 = as asked, 0.5 = half, 0 = paused).
    var rateScale: Double {
        get { lock.withLock { scale } }
        set { lock.withLock { scale = max(0, newValue) } }
    }

    func setThermalLevel(_ level: ThermalLevel) { rateScale = Self.scale(for: level) }

    static func scale(for level: ThermalLevel) -> Double {
        switch level {
        case .nominal: return 1
        case .fair: return 0.8
        case .serious: return 0.5
        case .critical: return 0.25
        }
    }

    /// True if work `key` may run at `now` (seconds) without exceeding `fps` (× `rateScale`).
    func admit(_ key: String, fps: Int, now: Double) -> Bool {
        lock.withLock {
            let rate = Double(fps) * scale
            guard rate > 0 else { return false }
            if let last = lastRun[key], now - last < 1 / rate { return false }
            lastRun[key] = now
            return true
        }
    }

    /// Drop while busy: true (and marks `key` busy) only if no work for `key` is running. Pair with `end(_:)`.
    func begin(_ key: String) -> Bool { lock.withLock { busy.insert(key).inserted } }

    func end(_ key: String) { lock.withLock { _ = busy.remove(key) } }

    func reset() { lock.withLock { lastRun.removeAll(); busy.removeAll() } }
}
