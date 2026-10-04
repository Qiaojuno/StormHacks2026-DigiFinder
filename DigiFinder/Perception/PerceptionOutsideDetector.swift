import Foundation
import DigiFinderCore

/// Inside vs outside (§5.2): default inside. Outside when YOLO sees outdoor classes and no Shelf for ~3 s;
/// back inside once shelves are seen for ~1 s. Reports changes only.
struct PerceptionOutsideDetector {
    /// Outdoor cues, all within `ObjectDetectionService.essentialLabels`.
    /// Empty (owner decision: object detection is only for obstacles). "I'm outside" by voice still works.
    static let outdoorLabels: Set<String> = []
    static let indoorLabels: Set<String> = ["Shelf"]
    var outsideAfter = 3.0
    var insideAfter = 1.0
    /// How long one sighting keeps counting (YOLO flickers).
    var memory = 1.0

    private(set) var isOutside = false
    private var outdoorSince: Double?
    private var lastOutdoor = -Double.infinity
    private var lastShelf = -Double.infinity
    private var shelfSince: Double?

    /// New state when it changes, else nil.
    mutating func update(_ detections: [Detection], time t: Double) -> Bool? {
        let outdoor = detections.contains { Self.outdoorLabels.contains($0.label) && $0.confidence >= 0.35 }
        let shelf = detections.contains { Self.indoorLabels.contains($0.label) && $0.confidence >= 0.35 }
        if outdoor { lastOutdoor = t }
        if shelf {
            if t - lastShelf > memory { shelfSince = t }
            lastShelf = t
        } else if t - lastShelf > memory {
            shelfSince = nil
        }
        let outdoorNow = t - lastOutdoor <= memory
        let shelfNow = t - lastShelf <= memory
        if outdoorNow && !shelfNow {
            if outdoorSince == nil { outdoorSince = t }
        } else {
            outdoorSince = nil
        }
        if !isOutside, let s = outdoorSince, t - s >= outsideAfter, t - lastShelf >= outsideAfter {
            isOutside = true
            return true
        }
        if isOutside, let s = shelfSince, t - s >= insideAfter {
            isOutside = false
            outdoorSince = nil
            return false
        }
        return nil
    }
}
