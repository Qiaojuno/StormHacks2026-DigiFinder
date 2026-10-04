import Foundation
import DigiFinderCore

/// Corridor, closing speed / TTC, threat level and steer, once per depth frame (§5.3). Wraps Core geometry.
/// Safety lane only: the controller serializes calls.
///
/// The app supplements the cane, so only real threats alert (`assessThreat`): things moving toward the user, and
/// chest/head-height things the cane passes under while the user walks toward them. Walls, shelves, tables, boxes,
/// things off to the side, and anything near a user who is standing or sitting still stay silent.
/// Only the motion state (walking / standing) changes the rules; the shopping phase never does.
final class DangerDetector {
    struct Reading {
        var obstacle: GeometryObstacle?
        var closingSpeed: Float?
        var timeToContact: Float?
        var steer: Steer = .unknown
        var threat: ThreatKind = .none
        /// Why the obstacle is or isn't a threat (debug overlay).
        var reason = ""
        /// The threat held for `consecutiveFrames` frames in a row.
        var emergency = false
    }

    /// Frames in a row a threat must hold before it alerts (fewer false alarms than the spec's 2). Verify on device.
    static let consecutiveFrames = 3
    /// Lanyard swing: no alerts while rotating faster than this (rad/s).
    static let maxRotation: Double = 1.5
    /// Steering is only worked out for obstacles nearer than this.
    static let steerRange: Float = 3.5

    private var rule = GeometryDangerRule()
    private var streak = 0
    private var walking = false

    /// `label`: YOLO name of the obstacle (projected into Stream B); known movers need less evidence.
    func evaluate(_ pts: [Vec3], t: Double, rotationRate: Double, walking isWalking: Bool,
                  floorY: Float?, label: (GeometryObstacle) -> String?) -> Reading {
        // The corridor changes with the motion state, so the distance history restarts with it.
        if isWalking != walking {
            walking = isWalking
            reset()
        }
        // Standing: nothing within 0.8 m (the user's hand and the held item at the shelf).
        let corridor = Corridor(minForward: isWalking ? 0.2 : ThreatTuning.stillMinDistance)
        let obstacle = corridorObstacle(pts, c: corridor)
        _ = rule.update(t: t, distance: obstacle?.distance, rotationRate: rotationRate)
        let closing = rule.history.closingSpeed

        var r = Reading(obstacle: obstacle, closingSpeed: closing, timeToContact: rule.history.timeToContact)
        let rotating = !rotationRate.isFinite || abs(rotationRate) >= Self.maxRotation
        if let o = obstacle {
            let input = ThreatInput(distance: o.distance, x: o.x, closing: closing, walking: isWalking,
                                    grounded: isGrounded(pts, obstacle: o, floorY: floorY, corridor: corridor),
                                    label: label(o))
            (r.threat, r.reason) = assessThreat(input)
            if rotating { r.reason = "rotating" }
        } else {
            r.reason = "path clear"
        }
        streak = (r.threat != .none && !rotating) ? streak + 1 : 0
        r.emergency = streak >= Self.consecutiveFrames
        if let o = obstacle, o.distance < Self.steerRange {
            r.steer = steerDirection(pts, obstacleX: o.x, obstacleZ: o.distance, corridor: corridor)
        }
        return r
    }

    func reset() {
        rule.reset()
        streak = 0
    }
}
