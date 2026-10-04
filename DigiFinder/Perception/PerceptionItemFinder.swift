import Foundation
import DigiFinderCore

/// Finds the goal item itself in the 0.5× view (owner decision: every search looks first; nearby mode only looks):
/// its YOLO class ("Mug", "Mobile phone", "Banana") if it has one, else product label text matching the goal's
/// words (sign text and price tags excluded). Direction from Stream B geometry, distance from LiDAR when in range.
enum PerceptionItemFinder {
    struct Sighting: Equatable {
        var box: NormRect
        var clock: Int
        var distance: Float?
    }

    static let minDetectionConfidence: Float = 0.4
    static let minTextConfidence: Float = 0.3

    static func find(goal: Goal, candidates: [ProductInfo], detections: [Detection], lines: [PerceptionTextRegion],
                     signBoxes: [NormRect], geometry: PerceptionFrameGeometry,
                     depthAt: (NormPoint) -> Float?) -> Sighting? {
        var box: NormRect?
        if let cls = goal.visualClass {
            box = detections.filter { $0.label == cls && $0.confidence >= minDetectionConfidence }
                .max { $0.box.area < $1.box.area }?.box
        }
        if box == nil {
            var terms = [goal.product] + goal.synonyms
            if let b = goal.brand { terms.append(b) }
            terms += candidates.prefix(10).map(\.name)
            let normalized = terms.map(normalizeText).filter { $0.count >= 3 }
            let hits = lines.filter { l in
                guard l.confidence >= minTextConfidence, !isPriceTag(l.text),
                      !signBoxes.contains(where: { $0.intersection(l.box) != nil }) else { return false }
                let text = normalizeText(l.text)
                return normalized.contains { fuzzyContains(text, $0) }
            }
            box = hits.max { $0.box.area < $1.box.area }?.box
        }
        guard let b = box else { return nil }
        let c = b.center
        return Sighting(box: b, clock: geometry.clock(c.x), distance: depthAt(c))
    }
}
