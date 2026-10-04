import Foundation

/// Sliding-window limit (Open Food Facts: 10 searches per minute per IP). Thread-safe.
final class NetworkRateLimiter {
    let limit: Int
    let window: TimeInterval

    private let lock = NSLock()
    private var sent: [TimeInterval] = []

    init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Records a call and returns true when it fits in the window; false = don't send it.
    func tryAcquire(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        sent.removeAll { now - $0 >= window }
        guard sent.count < limit else { return false }
        sent.append(now)
        return true
    }
}
