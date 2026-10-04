// Frozen app contracts (§3.3). Change requests go to CONTRACT_CHANGES.md.
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import simd
import DigiFinderCore

/// One Stream B (0.5× ultra-wide) video frame.
struct FrameB {
    let pixelBuffer: CVPixelBuffer
    let intrinsics: simd_float3x3?
    let time: CMTime
}

/// One Stream A (LiDAR) depth frame.
struct DepthFrame {
    let depth: AVDepthData
    let time: CMTime
}

struct CaptureCapabilities {
    var cameraAvailable = false
    var hasLiDAR = false
    var hasUltraWide = false
    var isMultiCam = false
}

protocol FrameSource: AnyObject {
    var capabilities: CaptureCapabilities { get }
    /// bufferingNewest(1)
    var streamB: AsyncStream<FrameB> { get }
    /// Safety lane, called on the capture queue.
    var onDepth: ((DepthFrame) -> Void)? { get set }
    /// Full-res 0.5×, upright.
    func captureStill() async throws -> CGImage
    func start() throws
    func stop()
}

protocol DepthProvider {
    /// Leveled points (+x right, +y up, +z forward) from a depth frame and CoreMotion gravity (device frame).
    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3]
    /// Distance in meters at an upright-portrait normalized point, if known.
    func distance(at p: NormPoint, _ f: DepthFrame) -> Float?
}
