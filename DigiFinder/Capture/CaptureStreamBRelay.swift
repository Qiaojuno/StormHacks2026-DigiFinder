import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import simd

/// Stream B video delegate (own serial queue): rate cap, intrinsics, and fan-out to every `makeStream()`
/// subscriber, each `bufferingNewest(1)` so a slow consumer only ever sees the latest frame.
final class CaptureStreamBRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let calibration: CaptureCalibration
    private let lock = NSLock()
    private var extras: [UUID: AsyncStream<FrameB>.Continuation] = [:]
    private var gate = CaptureRateGate()
    private var meter = CaptureRateMeter()
    private var dropped = 0

    init(calibration: CaptureCalibration) {
        self.calibration = calibration
        super.init()
    }

    deinit {
        extras.values.forEach { $0.finish() }
    }

    func setMaxFPS(_ fps: Double) { lock.withLock { gate.setMaxFPS(fps) } }

    var fps: Double { lock.withLock { meter.fps } }
    var droppedCount: Int { lock.withLock { dropped } }

    func makeStream() -> AsyncStream<FrameB> {
        let (s, c) = AsyncStream.makeStream(of: FrameB.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.withLock { extras[id] = c }
        c.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.extras.removeValue(forKey: id) }
        }
        return s
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let targets: [AsyncStream<FrameB>.Continuation]? = lock.withLock {
            guard gate.admit(time.seconds) else { return nil }
            meter.tick(time.seconds)
            return Array(extras.values)
        }
        guard let targets, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let K = Self.intrinsics(of: sampleBuffer)
        if let K {
            calibration.update(K, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        }
        let frame = FrameB(pixelBuffer: pixelBuffer, intrinsics: K, time: time)
        for c in targets { c.yield(frame) }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock { dropped += 1 }
    }

    /// Per-frame intrinsics (relative to the buffer size) when delivery is enabled on the connection.
    static func intrinsics(of sampleBuffer: CMSampleBuffer) -> simd_float3x3? {
        guard let data = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                         attachmentModeOut: nil) as? Data,
              data.count >= MemoryLayout<simd_float3x3>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: simd_float3x3.self) }
    }
}
