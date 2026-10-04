import CoreGraphics
import CoreVideo
import Foundation
import Vision
import DigiFinderCore

/// Follows one box (from the Gemini item finder) frame to frame on Stream B with Vision object tracking.
/// Boxes are contract space (upright portrait, normalized, top-left origin); Vision works in the same upright image
/// because every frame is handed over with `CaptureOrientation.visionOrientation` (flip setting included).
/// Vision queue only (not thread-safe).
final class PerceptionTargetTracker {
    enum Update: Equatable {
        case tracked(NormRect, confidence: Float)
        /// Low tracker confidence, or the box left the frame: tracking stopped.
        case lost
    }

    /// Below this tracker confidence the box counts as lost.
    static let minConfidence: Float = 0.3
    /// Lost when less than this share of the box is inside the frame.
    static let minVisibleShare = 0.5
    /// Lost when the box shrinks below this area (normalized).
    static let minArea = 0.0004

    private var handler = VNSequenceRequestHandler()
    private var last: VNDetectedObjectObservation?
    private(set) var box: NormRect?
    private(set) var confidence: Float = 0

    var isTracking: Bool { last != nil }

    /// Starts following `rect` from the next frame.
    func seed(_ rect: NormRect) {
        let r = rect.clamped()
        guard r.area >= Self.minArea else { stop(); return }
        handler = VNSequenceRequestHandler()             // fresh tracker state per target
        last = VNDetectedObjectObservation(boundingBox: CGRect(x: r.x, y: 1 - r.maxY, width: r.width, height: r.height))
        box = r
        confidence = 1
    }

    func stop() {
        last = nil
        box = nil
        confidence = 0
    }

    /// nil when not tracking.
    func update(_ pixelBuffer: CVPixelBuffer) -> Update? {
        guard let observation = last else { return nil }
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        guard (try? handler.perform([request], on: pixelBuffer, orientation: CaptureOrientation.visionOrientation)) != nil,
              let result = request.results?.first as? VNDetectedObjectObservation else {
            stop()
            return .lost
        }
        let bb = result.boundingBox
        let raw = Geometry.fromVision(NormRect(x: Double(bb.minX), y: Double(bb.minY),
                                               width: Double(bb.width), height: Double(bb.height)))
        let visible = raw.clamped()
        let share = raw.area > 0 ? visible.area / raw.area : 0
        guard result.confidence >= Self.minConfidence, share >= Self.minVisibleShare, visible.area >= Self.minArea else {
            stop()
            return .lost
        }
        last = result
        box = visible
        confidence = result.confidence
        return .tracked(visible, confidence: result.confidence)
    }
}
