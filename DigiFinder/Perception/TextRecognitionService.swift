import CoreGraphics
import Foundation
import Vision
import DigiFinderCore

/// Apple Vision text recognition (§9 Vision requests). One instance per queue: requests are reused and not
/// thread-safe. `.fast` for signs, shelf labels and doors on Stream B; `.accurate` for held-item stills.
final class TextRecognitionService {
    let request: VNRecognizeTextRequest
    var minConfidence: Float = 0.3

    init(level: VNRequestTextRecognitionLevel) {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "fr-FR"]
        if level == .fast { request.minimumTextHeight = 0.01 }
    }

    /// Region of interest in contract space (nil = whole image).
    func setRegion(_ r: NormRect?) {
        guard let r = r?.clamped(), r.area > 0 else { request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1); return }
        // Vision's ROI is bottom-left origin.
        request.regionOfInterest = CGRect(x: r.x, y: 1 - r.y - r.height, width: r.width, height: r.height)
    }

    /// Lines from the last `perform` that included `request`, converted to contract space.
    func results() -> [PerceptionTextRegion] {
        let roi = request.regionOfInterest
        return (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first, top.confidence >= minConfidence else { return nil }
            let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            // Boxes are relative to the ROI; map back to the full image.
            let b = obs.boundingBox
            let full = NormRect(x: Double(roi.origin.x + b.origin.x * roi.width), y: Double(roi.origin.y + b.origin.y * roi.height),
                                width: Double(b.width * roi.width), height: Double(b.height * roi.height))
            return PerceptionTextRegion(text: text, confidence: top.confidence, box: Geometry.fromVision(full).clamped())
        }
    }
}
