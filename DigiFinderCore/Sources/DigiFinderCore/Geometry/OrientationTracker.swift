import Foundation

/// Which way up the phone hangs on the lanyard, from gravity (owner decision: automatic, replaces the flip button).
/// Gravity is CoreMotion's, in the device frame, in g, pointing down: upright portrait ≈ (0, -1, 0), upside down
/// ≈ (0, +1, 0). Flat or sideways (|y| small) changes nothing; a new way up must hold for `hold` s (lanyard swing).
public struct OrientationTracker {
    public static let threshold: Float = 0.5
    public static let hold: Double = 1.0

    public private(set) var upsideDown: Bool
    private var since: Double?

    public init(upsideDown: Bool = false) { self.upsideDown = upsideDown }

    /// The new value when the way up changes, else nil.
    public mutating func update(gravityY y: Float, t: Double) -> Bool? {
        let wants: Bool? = y > Self.threshold ? true : (y < -Self.threshold ? false : nil)
        guard let w = wants, w != upsideDown else {
            since = nil
            return nil
        }
        let start = since.flatMap { t >= $0 ? $0 : nil } ?? t
        since = start
        guard t - start >= Self.hold else { return nil }
        upsideDown = w
        since = nil
        return w
    }
}
