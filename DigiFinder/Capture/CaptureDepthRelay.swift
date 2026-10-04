import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// Stream A depth delegate (own serial queue = the capture queue `onDepth` runs on). The safety-lane handler runs
/// first and synchronously; late frames are discarded by AVFoundation while it is busy. Debug digests come after.
final class CaptureDepthRelay: NSObject, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: ((DepthFrame) -> Void)?
    private var gate = CaptureRateGate()
    private var meter = CaptureRateMeter()
    private var dropped = 0
    private var debugEnabled = false
    private var lastDigest = -Double.infinity
    private var summary: CaptureDepthSummary?
    private var heatmap: CGImage?

    var handler: ((DepthFrame) -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    func setMaxFPS(_ fps: Double) { lock.withLock { gate.setMaxFPS(fps) } }
    func setDebugEnabled(_ on: Bool) { lock.withLock { debugEnabled = on; if !on { heatmap = nil } } }

    var fps: Double { lock.withLock { meter.fps } }
    var droppedCount: Int { lock.withLock { dropped } }
    var latestSummary: CaptureDepthSummary? { lock.withLock { summary } }
    var latestHeatmap: CGImage? { lock.withLock { heatmap } }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime,
                         connection: AVCaptureConnection) {
        let t = timestamp.seconds
        let (admitted, handler): (Bool, ((DepthFrame) -> Void)?) = lock.withLock {
            guard gate.admit(t) else { return (false, nil) }
            meter.tick(t)
            return (true, _handler)
        }
        guard admitted else { return }
        let depth = CaptureDepthMap.float32(depthData) ?? depthData
        handler?(DepthFrame(depth: depth, time: timestamp))

        let (digest, drawHeatmap): (Bool, Bool) = lock.withLock {
            guard t - lastDigest >= 0.5 else { return (false, false) }
            lastDigest = t
            return (true, debugEnabled)
        }
        guard digest else { return }
        let s = CaptureDepthSummary.make(from: depth, time: t)
        let h = drawHeatmap ? CaptureImageRenderer.depthHeatmap(depth) : nil
        lock.withLock { summary = s; if drawHeatmap { heatmap = h } }
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didDrop depthData: AVDepthData, timestamp: CMTime,
                         connection: AVCaptureConnection, reason: AVCaptureOutput.DataDroppedReason) {
        lock.withLock { dropped += 1 }
    }
}
