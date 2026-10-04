import Foundation
import DigiFinderCore

/// Read-only values for the debug overlay (§6): boxes, OCR regions, hand point. All in contract space.
struct PerceptionDebugSnapshot {
    var mode: PerceptionMode = .idle
    var modelLoaded = false
    /// Catalog `visualClasses` the model doesn't know (checked at load).
    var unknownVisualClasses: [String] = []
    var detections: [Detection] = []
    var textRegions: [PerceptionTextRegion] = []
    var signs: [AisleSign] = []
    var handTip: NormPoint?
    var pointedSpot: NormPoint?
    var pointedRegion: NormRect?
    var targetRegion: NormRect?
    /// Gemini item finder box being tracked (Vision), and the tracker's confidence.
    var trackedBox: NormRect?
    var trackConfidence: Float = 0
    var doors: [DoorObservation] = []
    var isOutside = false
    var yoloFPS: Double = 0
    var visionFPS: Double = 0
    /// Last held-item text and barcode (hold-up check).
    var heldLabel: String = ""
    var heldBarcode: String?
    /// Last event sent, for the overlay's log line.
    var lastEvent: String = ""
}
