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

    /// Alert sensitivity by place (store: sensitive; general: calm, collision course, crowd damping).
    var profile: ThreatProfile = .general {
        didSet { if profile != oldValue { reset() } }
    }
    /// Sideways-speed window (s).
    static let lateralWindow = 0.5
    /// Lanyard swing: no alerts while rotating faster than this (rad/s).
    static let maxRotation: Double = 1.5
    /// Steering is only worked out for obstacles nearer than this.
    static let steerRange: Float = 3.5

    private var rule = GeometryDangerRule()
    private var streak = 0
    private var walking = false
    /// Recent (time, lateral offset) of the nearest obstacle, for its sideways speed.
    private var lateral: [(t: Double, x: Float)] = []

    /// `label`: YOLO name of the obstacle (projected into Stream B); known movers need less evidence.
    func evaluate(_ pts: [Vec3], t: Double, rotationRate: Double, walking isWalking: Bool,
                  floorY: Float?, peopleInView: Int = 0, label: (GeometryObstacle) -> String?) -> Reading {
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
            lateral.append((t, o.x))
            lateral.removeAll { t - $0.t > Self.lateralWindow || $0.t > t }
            let input = ThreatInput(distance: o.distance, x: o.x, closing: closing, walking: isWalking,
                                    grounded: isGrounded(pts, obstacle: o, floorY: floorY, corridor: corridor),
                                    label: label(o), lateralSpeed: Self.slope(lateral), peopleInView: peopleInView)
            (r.threat, r.reason) = assessThreat(input, profile: profile)
            if rotating { r.reason = "rotating" }
        } else {
            lateral.removeAll()
            r.reason = "path clear"
        }
        streak = (r.threat != .none && !rotating) ? streak + 1 : 0
        r.emergency = streak >= profile.consecutiveFrames
        if let o = obstacle, o.distance < Self.steerRange {
            r.steer = steerDirection(pts, obstacleX: o.x, obstacleZ: o.distance, corridor: corridor)
        }
        return r
    }

    func reset() {
        rule.reset()
        streak = 0
        lateral.removeAll()
    }

    /// Least-squares slope (m/s) of x over time; nil with too few samples or no time spread.
    static func slope(_ h: [(t: Double, x: Float)]) -> Float? {
        guard h.count >= 3, let first = h.first?.t, let last = h.last?.t, last - first >= 0.15 else { return nil }
        let n = Double(h.count)
        let mt = h.map(\.t).reduce(0, +) / n
        let mx = h.map { Double($0.x) }.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for p in h { num += (p.t - mt) * (Double(p.x) - mx); den += (p.t - mt) * (p.t - mt) }
        return den > 0 ? Float(num / den) : nil
    }
}
