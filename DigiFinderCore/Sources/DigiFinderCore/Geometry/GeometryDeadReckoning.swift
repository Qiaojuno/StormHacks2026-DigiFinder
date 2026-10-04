import Foundation

// Aisle arrival by dead reckoning (§5.2): the camera only sees ~10:30–1:30, so a sign is never seen at 9 or 3.
// Remember the target sign's last bearing and distance, move the user with yaw + pedometer (~0.7 m per step),
// and report arrival when the predicted bearing passes ~70° to the side → "Stop. Aisle 6 is at 9 o'clock."
//
// Headings are degrees clockwise (turning right increases them). CoreMotion yaw grows counterclockwise,
// so pass `-yawDegrees`.

public struct GeometryDeadReckoning: Equatable {
    public var stepLength: Double
    /// Target and user positions in a flat world frame anchored at the sighting (meters, x right of heading 0, y ahead).
    public private(set) var targetX: Double
    public private(set) var targetY: Double
    public private(set) var userX = 0.0
    public private(set) var userY = 0.0
    public private(set) var lastSteps: Int

    /// `bearingDegreesRight`: target bearing relative to `heading` when seen; `steps`: the pedometer count then.
    public init(bearingDegreesRight: Double, distance: Double, heading: Double, steps: Int, stepLength: Double = 0.7) {
        let a = (heading + bearingDegreesRight) * .pi / 180
        let d = distance.isFinite ? max(distance, 0) : 0
        targetX = d * sin(a); targetY = d * cos(a)
        lastSteps = steps
        self.stepLength = stepLength
    }

    /// Re-anchor on a fresh sighting of the same target (keeps nothing from before).
    public mutating func resight(bearingDegreesRight: Double, distance: Double, heading: Double, steps: Int) {
        self = GeometryDeadReckoning(bearingDegreesRight: bearingDegreesRight, distance: distance, heading: heading,
                                     steps: steps, stepLength: stepLength)
    }

    /// Walks the steps taken since the last update along the current heading. A pedometer reset only re-bases.
    public mutating func update(heading: Double, steps: Int) {
        let delta = steps - lastSteps
        lastSteps = steps
        guard delta > 0, heading.isFinite else { return }
        let a = heading * .pi / 180
        let d = Double(delta) * stepLength
        userX += d * sin(a); userY += d * cos(a)
    }

    /// Meters from the user to the target.
    public var distance: Double { hypot(targetX - userX, targetY - userY) }

    /// Target bearing right of `heading`, in (-180, 180].
    public func bearing(heading: Double) -> Double {
        let world = atan2(targetX - userX, targetY - userY) * 180 / .pi
        return Geometry.relativeDegreesRight(heading: heading, target: world)
    }

    public func clock(heading: Double) -> Int { clockPosition(degreesRight: bearing(heading: heading)) }

    /// The target is now beside (or behind) the user: |bearing| ≥ `threshold` degrees.
    public func hasPassedSide(heading: Double, threshold: Double = 70) -> Bool {
        abs(bearing(heading: heading)) >= threshold
    }
}
