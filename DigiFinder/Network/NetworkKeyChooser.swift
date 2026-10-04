import Foundation

/// Which Gemini key to try first (main, then fallback). Thread-safe; shared by every request of one client.
/// A refused key is skipped for a while, then the main key is tried again.
final class NetworkKeyChooser: @unchecked Sendable {
    /// HTTP statuses that mean "this key can't be used right now": unauthorized, no credit, blocked/disabled, quota.
    static let refused: Set<Int> = [401, 402, 403, 429]
    /// How long a refused key is skipped before it's tried first again (s).
    static let retryAfter: Double = 300

    private let count: Int
    private let lock = NSLock()
    private var skippedUntil: [Int: Double] = [:]

    init(count: Int) { self.count = count }

    /// Keys to try for one request: usable ones in main → fallback order, then skipped ones as a last resort.
    func order() -> [Int] {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        let all = Array(0..<count)
        let ready = all.filter { (skippedUntil[$0] ?? 0) <= now }
        return ready + all.filter { !ready.contains($0) }
    }

    func refused(_ index: Int) {
        lock.lock(); skippedUntil[index] = ProcessInfo.processInfo.systemUptime + Self.retryAfter; lock.unlock()
    }

    func worked(_ index: Int) {
        lock.lock(); skippedUntil[index] = nil; lock.unlock()
    }
}
