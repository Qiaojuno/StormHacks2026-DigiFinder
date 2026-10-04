import CoreGraphics
import Foundation
import DigiFinderCore

/// Simulator / no camera: "Camera unavailable". Never yields frames, never calls `onDepth`.
final class NoCameraSource: FrameSource, CaptureControl, @unchecked Sendable {
    let capabilities = CaptureCapabilities()
    let streamB: AsyncStream<FrameB>
    var onDepth: ((DepthFrame) -> Void)?
    var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?
    var debugOverlayEnabled = false
    /// Why there is no camera (debug overlay).
    let reason: String

    private let lock = NSLock()
    // Held so the streams stay open (no frames, no finish) like a camera that never delivers.
    private var continuations: [AsyncStream<FrameB>.Continuation] = []

    init(reason: String = "No camera") {
        self.reason = reason
        let (stream, continuation) = AsyncStream.makeStream(of: FrameB.self, bufferingPolicy: .bufferingNewest(1))
        streamB = stream
        continuations = [continuation]
    }

    deinit { continuations.forEach { $0.finish() } }

    func captureStill() async throws -> CGImage { throw CaptureError.unavailable }
    func start() throws {}
    func stop() {}

    func setThermalLevel(_ level: ThermalLevel) {}
    func setRates(_ rates: CaptureRates) {}
    var rates: CaptureRates { .full }

    func makeStreamB() -> AsyncStream<FrameB> {
        let (stream, continuation) = AsyncStream.makeStream(of: FrameB.self, bufferingPolicy: .bufferingNewest(1))
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    var debugInfo: CaptureDebugInfo { CaptureDebugInfo(backend: reason) }
    var latestDepthSummary: CaptureDepthSummary? { nil }
    var latestDebugImage: CGImage? { nil }
    var latestDepthHeatmap: CGImage? { nil }
}
