import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// The LiDAR camera's 1× video: rendered to a small upright preview (~2 Hz) only while the debug overlay is on.
final class CaptureDebugVideoRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let previewWidth: CGFloat = 360

    private let lock = NSLock()
    private var enabled = false
    private var lastRender = -Double.infinity
    private var image: CGImage?

    func setEnabled(_ on: Bool) { lock.withLock { enabled = on; if !on { image = nil } } }
    var latestImage: CGImage? { lock.withLock { image } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let render: Bool = lock.withLock {
            guard enabled, t - lastRender >= 0.5 else { return false }
            lastRender = t
            return true
        }
        guard render, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let preview = CaptureImageRenderer.upright(pixelBuffer, maxWidth: Self.previewWidth)
        lock.withLock { if enabled { image = preview } }
    }
}
