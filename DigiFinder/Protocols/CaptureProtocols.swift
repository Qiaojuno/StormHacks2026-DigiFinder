// App contracts (§3.3). Change requests go to CONTRACT_CHANGES.md.
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
    /// A new Stream B subscription (bufferingNewest(1)) per call; each consumer calls it once and iterates its own
    /// stream (an `AsyncStream` supports one consumer only).
    func makeStreamB() -> AsyncStream<FrameB>
    /// Safety lane, called on the capture queue. Shared: every consumer chains
    /// (`let previous = frames.onDepth; frames.onDepth = { f in mine(f); previous?(f) }`) and never replaces it.
    var onDepth: ((DepthFrame) -> Void)? { get set }
    /// Full-res 0.5×, upright.
    func captureStill() async throws -> CGImage
    /// Shows the live 0.5× (Stream B) feed in `layer` (main-screen background). Connected once the session is
    /// configured; no-op without a camera. Call from the main thread.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer)
    /// Returns at once; asks for permission and configures on a background queue. Throws `CaptureError.denied`
    /// when camera permission is already denied.
    func start() throws
    func stop()

    /// Called (any queue) when `capabilities` change after `start()`: permission answered, session configured, or
    /// configuration failed (`cameraAvailable` false → the runner sends `.system(.cameraDenied)`).
    var onCapabilitiesChange: ((CaptureCapabilities) -> Void)? { get set }
    /// Thermal hook (§5.16): lowers Stream B first, depth only when critical. Any thread.
    func setThermalLevel(_ level: ThermalLevel)
    /// Explicit caps (combined with the thermal caps by minimum; one value, last writer wins). Any thread.
    func setRates(_ rates: CaptureRates)
    /// Effective caps now.
    var rates: CaptureRates { get }
    /// Latest Stream B intrinsics + buffer size (landscape sensor pixels), nil until the first frame / without a camera.
    var streamBCalibration: CaptureCalibration.StreamB? { get }

    // Debug overlay (read-only snapshots, safe from any thread).
    var debugInfo: CaptureDebugInfo { get }
    var latestDepthSummary: CaptureDepthSummary? { get }
    /// Upright 1× preview (~2 Hz) while `debugOverlayEnabled`.
    var latestDebugImage: CGImage? { get }
    /// Upright depth heatmap (red near, blue far, black invalid; ~2 Hz) while `debugOverlayEnabled`.
    var latestDepthHeatmap: CGImage? { get }
    /// Turns on the preview and heatmap rendering (off by default to save power).
    var debugOverlayEnabled: Bool { get set }
}

protocol DepthProvider {
    /// Leveled points (+x right, +y up, +z forward) from a depth frame and CoreMotion gravity (device frame).
    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3]
    /// `p` is a point of Stream B's upright portrait image (the only image perception sees). Result: meters along the
    /// viewing ray (median of a 5×5 depth window); nil outside the LiDAR field of view (about half the 0.5× image).
    func distance(at p: NormPoint, _ f: DepthFrame) -> Float?
}
