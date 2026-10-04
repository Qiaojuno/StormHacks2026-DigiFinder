import Foundation
import DigiFinderCore

/// Arrival by dead reckoning (§5.2 arrival, §5.6): remembers the target sign's last bearing and distance, moves the
/// user with yaw + pedometer, and reports once when the sign passes ~70° to the side (aisle) or comes within ~2 m
/// (destination). Headings are clockwise degrees: pass `-motion.yawDegrees`.
struct PerceptionArrivalTracker {
    enum Kind { case aisle, destination }

    var sideThreshold = 70.0
    var destinationRadius = 2.0
    /// Forget a sign not seen for this long (seconds).
    var expiry = 90.0

    private(set) var reckoning: GeometryDeadReckoning?
    private(set) var key: String?
    private var sightedSteps = 0
    private var lastSeen = -Double.infinity
    private var lastSightDistance = Double.infinity
    private var arrivedKeys = Set<String>()

    mutating func reset() { self = PerceptionArrivalTracker(sideThreshold: sideThreshold, destinationRadius: destinationRadius, expiry: expiry) }

    /// A fresh sighting of a matching sign.
    mutating func sighted(key k: String, bearing: Double, distance: Double, heading: Double, steps: Int, time t: Double) {
        if var r = reckoning, key == k {
            r.resight(bearingDegreesRight: bearing, distance: distance, heading: heading, steps: steps)
            reckoning = r
        } else {
            reckoning = GeometryDeadReckoning(bearingDegreesRight: bearing, distance: distance, heading: heading, steps: steps)
            key = k
        }
        sightedSteps = steps
        lastSeen = t
        lastSightDistance = distance
    }

    /// Clock of the target when the user has just arrived (once per sign), else nil.
    mutating func update(kind: Kind, heading: Double, steps: Int, time t: Double) -> Int? {
        guard var r = reckoning, let k = key else { return nil }
        if t - lastSeen > expiry { reckoning = nil; key = nil; return nil }
        r.update(heading: heading, steps: steps)
        reckoning = r
        guard !arrivedKeys.contains(k) else { return nil }
        let walked = steps - sightedSteps
        let arrived: Bool
        switch kind {
        case .aisle:
            arrived = walked >= 2 && r.hasPassedSide(heading: heading, threshold: sideThreshold)
        case .destination:
            arrived = (lastSightDistance <= destinationRadius && t - lastSeen < 1)
                || (walked >= 1 && r.distance <= destinationRadius)
                || (walked >= 2 && r.distance <= destinationRadius * 2 && r.hasPassedSide(heading: heading, threshold: sideThreshold))
        }
        guard arrived else { return nil }
        arrivedKeys.insert(k)
        return r.clock(heading: heading)
    }
}
