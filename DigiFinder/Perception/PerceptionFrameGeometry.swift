import CoreVideo
import Foundation
import simd
import DigiFinderCore

/// Angles and box distances for one Stream B frame: its own intrinsics when present, else a nominal ultra-wide lens.
struct PerceptionFrameGeometry {
    /// Nominal horizontal FOV of the landscape ultra-wide sensor when a frame carries no intrinsics.
    static let nominalSensorFOVDegrees: Float = 100

    /// Buffer size in landscape sensor pixels.
    let sensorWidth: Int
    let sensorHeight: Int
    let intrinsics: Mat3

    init(_ f: FrameB) {
        sensorWidth = CVPixelBufferGetWidth(f.pixelBuffer)
        sensorHeight = CVPixelBufferGetHeight(f.pixelBuffer)
        let K = f.intrinsics ?? CameraGeometry.nominalIntrinsics(width: sensorWidth, height: sensorHeight,
                                                                   horizontalFOVDegrees: Self.nominalSensorFOVDegrees)
        intrinsics = CameraGeometry.mat3(K)
    }

    /// Upright still (no intrinsics): the portrait image's horizontal FOV is the sensor's vertical one.
    init(stillWidth: Int, stillHeight: Int) {
        sensorWidth = max(stillHeight, 1)
        sensorHeight = max(stillWidth, 1)
        intrinsics = CameraGeometry.mat3(CameraGeometry.nominalIntrinsics(
            width: sensorWidth, height: sensorHeight, horizontalFOVDegrees: Self.nominalSensorFOVDegrees))
    }

    /// Horizontal angle right of ahead (degrees) for an upright-portrait x.
    func degreesRight(_ x: Double) -> Double {
        Geometry.degreesRight(portraitX: x, intrinsics: intrinsics, sensorHeight: Double(sensorHeight))
    }

    func clock(_ x: Double) -> Int { clockPosition(degreesRight: degreesRight(x)) }

    /// Distance from the apparent height of an object of known size (meters), nil if the box is degenerate.
    func distance(boxHeight h: Double, objectHeight: Double) -> Float? {
        Geometry.distanceFromBoxHeight(normalizedHeight: h, objectHeight: objectHeight, intrinsics: intrinsics,
                                       sensorWidth: Double(sensorWidth)).map { Float($0) }
    }
}
