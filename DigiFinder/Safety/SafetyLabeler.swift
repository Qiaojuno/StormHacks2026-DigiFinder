import Foundation
import DigiFinderCore

/// Names the nearest obstacle (§5.3 step 6): the YOLO box on Stream B that overlaps the most projected obstacle
/// points, else "Obstacle". Uses whatever `detector.latest` holds and never waits for YOLO.
enum SafetyLabeler {
    static let fallbackLabel = "Obstacle"
    static let minConfidence: Float = 0.25
    /// A box must hold at least this share of the projected points (and at least `minPoints`).
    static let minShare = 0.2
    static let minPoints = 3
    /// Slack around boxes (normalized), for depth/video misregistration.
    static let boxMargin = 0.02
    static let maxDebugPoints = 40

    /// Parts of a person or worn items: named as the person.
    private static let personWords = ["person", "man", "woman", "boy", "girl"]
    /// Labels that never name an obstacle on their own.
    private static let ignored: Set<String> = ["clothing", "footwear", "fashion accessory"]

    struct Result: Equatable {
        var label: String
        var box: NormRect?
        /// Projected points (at most `maxDebugPoints`) for the debug overlay.
        var points: [NormPoint]
    }

    /// `points`: leveled obstacle points (`GeometryObstacle.points`); `basis`: the leveling used for this frame.
    static func label(points: [Vec3], basis: CameraGeometry.LevelBasis, lens: SafetyStreamBLens?,
                      detections: [Detection]) -> Result {
        guard let lens, !points.isEmpty else { return Result(label: fallbackLabel, box: nil, points: []) }
        let projected = points.compactMap { lens.project(CameraGeometry.unlevel($0, basis)) }
        let debugPoints = sample(projected, max: maxDebugPoints)
        guard projected.count >= minPoints else { return Result(label: fallbackLabel, box: nil, points: debugPoints) }

        let needed = max(minPoints, Int(Double(projected.count) * minShare))
        var best: (detection: Detection, count: Int)?
        for d in detections where d.confidence >= minConfidence && !ignored.contains(d.label.lowercased()) {
            let box = NormRect(x: d.box.x - boxMargin, y: d.box.y - boxMargin,
                               width: d.box.width + 2 * boxMargin, height: d.box.height + 2 * boxMargin)
            let n = projected.reduce(0) { $0 + (box.contains($1) ? 1 : 0) }
            guard n >= needed else { continue }
            if let b = best, n < b.count || (n == b.count && d.confidence <= b.detection.confidence) { continue }
            best = (d, n)
        }
        guard let b = best else { return Result(label: fallbackLabel, box: nil, points: debugPoints) }
        return Result(label: spokenName(b.detection.label), box: b.detection.box, points: debugPoints)
    }

    /// OIV7 label → the word spoken in "<Object> ahead": people and body parts become "Person".
    static func spokenName(_ label: String) -> String {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = l.lowercased()
        if personWords.contains(lower) || lower.hasPrefix("human ") { return "Person" }
        return l.isEmpty ? fallbackLabel : l
    }

    private static func sample(_ pts: [NormPoint], max n: Int) -> [NormPoint] {
        guard pts.count > n, n > 0 else { return pts }
        let step = Double(pts.count) / Double(n)
        return (0..<n).map { pts[Int(Double($0) * step)] }
    }
}
