import AVFoundation
import Foundation

/// No LiDAR (§2 Fallback): the ultra-wide alone, else the wide camera. Video + full-res stills, no depth
/// (`onDepth` is never called; distances come from `EstimatedDepthProvider`).
final class FallbackCameraService: CaptureSessionSource, @unchecked Sendable {
    private let device: AVCaptureDevice
    /// Horizontal field of view of the landscape sensor (= vertical field of view of the upright image), degrees.
    let fieldOfViewDegrees: Float

    init(device: AVCaptureDevice, calibration: CaptureCalibration = CaptureCalibration()) {
        let ultra = device.deviceType == .builtInUltraWideCamera
        self.device = device
        let fov = device.activeFormat.videoFieldOfView
        fieldOfViewDegrees = fov > 1 ? fov : (ultra ? 100 : 70)
        super.init(planned: CaptureCapabilities(cameraAvailable: true, hasUltraWide: ultra),
                   backend: ultra ? "ultra-wide" : "wide", calibration: calibration)
    }

    /// Ultra-wide, else wide; nil without a back camera (always nil in the Simulator).
    convenience init?(calibration: CaptureCalibration = CaptureCalibration()) {
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { return nil }
        self.init(device: device, calibration: calibration)
    }

    override func configureSession() -> CaptureSessionSetup? {
        let ultra = device.deviceType == .builtInUltraWideCamera
        return configureSingleCamera(device, backend: ultra ? "ultra-wide" : "wide",
                                     capabilities: CaptureCapabilities(cameraAvailable: true, hasUltraWide: ultra))
    }
}
