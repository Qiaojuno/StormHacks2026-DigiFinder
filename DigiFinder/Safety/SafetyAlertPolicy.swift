import Foundation

/// When to alert, repeat the vibrations and report the path clear (§5.3 alert sequence, steps 5–7).
/// Pure state; the controller serializes calls.
struct SafetyAlertPolicy {
    /// No second alert for the same obstacle within this many seconds.
    static let cooldown: Double = 5
    /// Still closing this long after the alert → vibrate once more (no speech).
    static let repeatAfter: Double = 2
    /// The path must stay open this long before `.dangerCleared`.
    static let clearHold: Double = 1
    /// An obstacle this far away (or none) leaves the path open.
    static let clearDistance: Float = 1.5
    /// The user stopped in front of the obstacle (not closing) this long → treat the path as open too, so guidance
    /// resumes with a fresh prompt (a new approach alerts again).
    static let stoppedHold: Double = 3
    /// Same label within this lateral distance (meters) = the same obstacle for the cooldown.
    static let sameObstacleX: Float = 0.8
    /// A different obstacle may interrupt an active alert after this long.
    static let retargetAfter: Double = 1
    /// Closing speed that counts as "still closing" (m/s).
    static let closingThreshold: Float = 0.2

    struct Alert: Equatable {
        var label: String
        var x: Float
        var t: Double
    }

    enum Update: Equatable { case none, pulse, cleared }

    private(set) var active: Alert?
    private var pulsed = false
    private var recent: [Alert] = []
    private var openSince: Double?
    private var stoppedSince: Double?

    var isActive: Bool { active != nil }

    /// Whether an emergency with this obstacle should raise a new alert now (cooldown, active alert).
    func wantsAlert(label: String, x: Float, t: Double) -> Bool {
        if let a = active {
            guard t - a.t >= Self.retargetAfter, !Self.same(a, label: label, x: x) else { return false }
        }
        return !recent.contains { t - $0.t >= 0 && t - $0.t < Self.cooldown && Self.same($0, label: label, x: x) }
    }

    mutating func didAlert(label: String, x: Float, t: Double) {
        let a = Alert(label: label, x: x, t: t)
        active = a
        pulsed = false
        openSince = nil
        stoppedSince = nil
        recent.removeAll { t - $0.t >= Self.cooldown || t < $0.t }
        recent.append(a)
    }

    /// Every reading after the emergency check. `distance` nil = nothing in the corridor.
    mutating func update(t: Double, emergency: Bool, distance: Float?, closing: Float?) -> Update {
        guard let a = active else { return .none }
        let closingNow = distance != nil && (closing ?? 0) > Self.closingThreshold
        if !pulsed && t - a.t >= Self.repeatAfter && closingNow {
            pulsed = true
            return .pulse
        }
        if emergency {
            openSince = nil
            stoppedSince = nil
            return .none
        }
        if (closing ?? 0) < 0.1 { stoppedSince = stoppedSince ?? t } else { stoppedSince = nil }
        let stopped = stoppedSince.map { t - $0 >= Self.stoppedHold } ?? false
        let open = distance.map { $0 >= Self.clearDistance } ?? true
        guard open || stopped else {
            openSince = nil
            return .none
        }
        let since = openSince ?? t
        openSince = since
        guard t - since >= Self.clearHold else { return .none }
        active = nil
        openSince = nil
        stoppedSince = nil
        return .cleared
    }

    mutating func reset() {
        active = nil
        pulsed = false
        recent.removeAll()
        openSince = nil
        stoppedSince = nil
    }

    private static func same(_ a: Alert, label: String, x: Float) -> Bool {
        a.label == label && abs(a.x - x) < sameObstacleX
    }
}
