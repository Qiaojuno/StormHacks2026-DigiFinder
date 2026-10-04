// Wave 1 compiling stubs. The Capture agent replaces these (one file per type).
import AVFoundation
import CoreGraphics
import CoreMedia
import DigiFinderCore

enum CaptureError: Error { case unavailable, stillFailed }

/// Simulator / no camera: "Camera unavailable".
final class NoCameraSource: FrameSource {
    let capabilities = CaptureCapabilities()
    let streamB = AsyncStream<FrameB> { _ in }
    var onDepth: ((DepthFrame) -> Void)?
    func captureStill() async throws -> CGImage { throw CaptureError.unavailable }
    func start() throws {}
    func stop() {}
}

/// LiDAR depth + 0.5× ultra-wide in one AVCaptureMultiCamSession (§9 Multi-cam setup).
final class MultiCamService: FrameSource {
    private(set) var capabilities = CaptureCapabilities()
    let streamB = AsyncStream<FrameB> { _ in }
    var onDepth: ((DepthFrame) -> Void)?
    func captureStill() async throws -> CGImage { throw CaptureError.unavailable }
    func start() throws {}
    func stop() {}
}

/// No LiDAR: ultra-wide (or wide) alone.
final class FallbackCameraService: FrameSource {
    private(set) var capabilities = CaptureCapabilities()
    let streamB = AsyncStream<FrameB> { _ in }
    var onDepth: ((DepthFrame) -> Void)?
    func captureStill() async throws -> CGImage { throw CaptureError.unavailable }
    func start() throws {}
    func stop() {}
}

struct LiDARDepthProvider: DepthProvider {
    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3] { [] }
    func distance(at p: NormPoint, _ f: DepthFrame) -> Float? { nil }
}

/// Distances from box size/growth (fallback, no LiDAR).
struct EstimatedDepthProvider: DepthProvider {
    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3] { [] }
    func distance(at p: NormPoint, _ f: DepthFrame) -> Float? { nil }
}

/// Per-stream rate limiting ("own serial queue, drop while busy", §3.6).
final class FrameScheduler {
    private var lastRun: [String: Double] = [:]

    /// True if work `key` may run at `now` (seconds) without exceeding `fps`.
    func admit(_ key: String, fps: Int, now: Double) -> Bool {
        guard fps > 0 else { return false }
        if let last = lastRun[key], now - last < 1 / Double(fps) { return false }
        lastRun[key] = now
        return true
    }
}
