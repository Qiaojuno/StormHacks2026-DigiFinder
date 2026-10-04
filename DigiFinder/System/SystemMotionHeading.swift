import CoreMotion
import Foundation

/// Heading of the back camera (device −Z) around the vertical axis, from a CoreMotion attitude.
/// Euler `attitude.yaw` is unusable here: an upright phone sits at pitch 90° (gimbal lock).
/// Degrees, counterclockwise positive like CoreMotion yaw (Core's dead reckoning takes `-yawDegrees`), -180...180.
enum SystemMotionHeading {
    static func yawDegrees(_ m: CMRotationMatrix, gravity g: SIMD3<Double>) -> Double? {
        let col3 = SIMD3(-m.m13, -m.m23, -m.m33)
        let row3 = SIMD3(-m.m31, -m.m32, -m.m33)
        // Pick the matrix convention whose "down" matches the measured gravity; the other one gives the camera axis.
        let rowsAreDeviceAxes = simdLength(col3 - g) <= simdLength(row3 - g)
        let forward = rowsAreDeviceAxes ? row3 : col3
        let top = rowsAreDeviceAxes ? SIMD3(m.m21, m.m22, m.m23) : SIMD3(m.m12, m.m22, m.m32)
        // Phone lying flat: the camera looks at the floor, so use the top edge instead.
        let axis = (forward.x * forward.x + forward.y * forward.y).squareRoot() > 0.3 ? forward : top
        guard (axis.x * axis.x + axis.y * axis.y).squareRoot() > 1e-3 else { return nil }
        return atan2(axis.y, axis.x) * 180 / .pi
    }

    private static func simdLength(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }
}
