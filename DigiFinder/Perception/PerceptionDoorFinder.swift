import Foundation
import DigiFinderCore

/// Doors for the entrance step without internet (§5.2): YOLO "Door" boxes, text on or near each door
/// ("Entrance", "Enter", "In" → entrance; "Exit", "Out" → exit), distance from LiDAR within ~5 m, else from the
/// box height (`fy × 2.1 m / boxHeightPx`, "about").
struct PerceptionDoorFinder {
    static let doorHeight = 2.1
    static let lidarRange: Float = 5
    var minConfidence: Float = 0.35

    static let entranceWords: Set<String> = ["entrance", "enter", "entree", "in", "entry", "welcome"]
    static let exitWords: Set<String> = ["exit", "out", "sortie"]

    struct Door: Equatable {
        var observation: DoorObservation
        var box: NormRect
    }

    /// Doors nearest first. `depthAt` returns LiDAR distance at a contract-space point (nil when unknown).
    func doors(detections: [Detection], text: [PerceptionTextRegion], geometry: PerceptionFrameGeometry,
               depthAt: (NormPoint) -> Float?) -> [Door] {
        let boxes = detections.filter { $0.label == "Door" && $0.confidence >= minConfidence }.map(\.box)
        var out: [Door] = []
        for box in boxes {
            let label = Self.label(for: box, text: text)
            var distance: Float?
            if let d = depthAt(box.center), d > 0, d <= Self.lidarRange { distance = d }
            if distance == nil { distance = geometry.distance(boxHeight: box.height, objectHeight: Self.doorHeight) }
            let obs = DoorObservation(clock: geometry.clock(box.midX), distance: distance, label: label)
            out.append(Door(observation: obs, box: box))
        }
        return out.sorted { ($0.observation.distance ?? .infinity) < ($1.observation.distance ?? .infinity) }
    }

    /// Text whose center lies on the door or just above it (signs over doors), widened by 25 % each side.
    static func label(for box: NormRect, text: [PerceptionTextRegion]) -> DoorLabel {
        let zone = NormRect(x: box.x - box.width * 0.25, y: box.y - box.height * 0.35,
                            width: box.width * 1.5, height: box.height * 1.35)
        var entrance = false, exit = false
        for t in text where zone.contains(t.box.center) {
            let words = Set(normalizedWords(t.text))
            if !words.isDisjoint(with: exitWords) { exit = true }
            if !words.isDisjoint(with: entranceWords) || words.contains("entrance") { entrance = true }
        }
        if entrance && !exit { return .entrance }
        if exit && !entrance { return .exit }
        return .unknown
    }
}
