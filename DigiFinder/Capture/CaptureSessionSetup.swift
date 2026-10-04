import AVFoundation
import Foundation

/// A configured (not yet running) session and what it delivers.
struct CaptureSessionSetup {
    let session: AVCaptureSession
    let photoOutput: AVCapturePhotoOutput?
    /// Camera behind Stream B (frame-rate and pressure control).
    let streamBDevice: AVCaptureDevice
    /// LiDAR camera when depth is connected.
    let depthDevice: AVCaptureDevice?
    let capabilities: CaptureCapabilities
    let backend: String
    let streamBFormat: String
    let depthFormat: String
    /// Highest Stream B frame rate the cost step-down allows.
    let streamBFrameCap: Double
}
