import Foundation
import DigiFinderCore

/// Corridor, closing speed / TTC, the 2-frame emergency rule (shelf mode, rotation gate, stationary rule) and steer,
/// once per depth frame (§5.3). Wraps Core geometry. Safety lane only: the controller serializes calls.
final class DangerDetector {
    struct Reading {
        var obstacle: GeometryObstacle?
        var closingSpeed: Float?
        var timeToContact: Float?
        var steer: Steer = .unknown
        /// The emergency rule held for 2 consecutive frames.
        var emergency = false
    }

    /// Stationary rule: with the user standing still a static object can't close in, so only a clearly moving
    /// object counts (m/s; LiDAR noise and lanyard sway stay below this). Verify on device (§10).
    static let stationaryMinClosing: Float = 0.35
    /// Walking while in shelf mode: whatever is ahead is most likely the shelf, so only fast movers count.
    static let shelfWalkingMinClosing: Float = 1.2
    /// The Core rule's own closing threshold.
    static let minClosing: Float = 0.2
    /// Steer lanes are only evaluated for obstacles nearer than this.
    static let steerRange: Float = 3.5

    private var rule = GeometryDangerRule()
    /// Consecutive frames passing the app-side stationary/shelf guards.
    private var guardStreak = 0
    private var shelfMode = false

    func evaluate(_ pts: [Vec3], t: Double, rotationRate: Double, walking: Bool, shelfMode shelf: Bool) -> Reading {
        if shelf != shelfMode {
            shelfMode = shelf
            reset()
        }
        let corridor = shelf ? Corridor.shelf : Corridor()
        let obstacle = corridorObstacle(pts, c: corridor)
        let ruleHolds = rule.update(t: t, distance: obstacle?.distance, rotationRate: rotationRate, shelfMode: shelf)

        let closing = rule.history.closingSpeed
        let needed: Float = shelf ? (walking ? Self.shelfWalkingMinClosing : Self.minClosing)
                                  : (walking ? Self.minClosing : Self.stationaryMinClosing)
        if let v = closing, v >= needed { guardStreak += 1 } else { guardStreak = 0 }

        var r = Reading(obstacle: obstacle, closingSpeed: closing, timeToContact: rule.history.timeToContact)
        r.emergency = ruleHolds && guardStreak >= rule.consecutiveFrames
        if let o = obstacle, o.distance < Self.steerRange {
            r.steer = steerDirection(pts, obstacleX: o.x, obstacleZ: o.distance)
        }
        return r
    }

    func reset() {
        rule.reset()
        guardStreak = 0
    }
}
