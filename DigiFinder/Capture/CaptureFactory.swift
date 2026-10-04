import AVFoundation
import Foundation

/// Picks the capture path for `AppEnvironment.live()` (§3.4): LiDAR + ultra-wide → ultra-wide → wide → no camera.
/// Only device discovery happens here; sessions are built on `start()`, after camera permission.
enum CaptureFactory {
    static func makeBest() -> (FrameSource, DepthProvider) {
        #if targetEnvironment(simulator)
        return (NoCameraSource(reason: "Simulator"), EstimatedDepthProvider())
        #else
        let calibration = CaptureCalibration()
        if let multi = MultiCamService(calibration: calibration) {
            return (multi, LiDARDepthProvider(calibration: calibration))
        }
        if let single = FallbackCameraService(calibration: calibration) {
            return (single, EstimatedDepthProvider(calibration: calibration, verticalFOVDegrees: single.fieldOfViewDegrees))
        }
        return (NoCameraSource(reason: "No back camera"), EstimatedDepthProvider())
        #endif
    }
}
