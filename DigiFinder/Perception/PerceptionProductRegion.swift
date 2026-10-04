import Foundation
import DigiFinderCore

/// One product's label text on the shelf (a block of nearby lines, price tags removed).
struct PerceptionProductRegion: Equatable {
    var text: String
    var box: NormRect
    var lines: [PerceptionTextRegion]

    /// Distance from `p` to the box (0 inside).
    func distance(to p: NormPoint) -> Double {
        let dx = max(box.x - p.x, 0, p.x - box.maxX)
        let dy = max(box.y - p.y, 0, p.y - box.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
