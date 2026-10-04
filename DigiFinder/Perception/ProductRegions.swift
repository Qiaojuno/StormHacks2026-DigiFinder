import Foundation
import DigiFinderCore

/// OCR product regions at the shelf (§5.2 point at the shelf): price tags filtered out, nearby lines merged.
enum ProductRegions {
    static func regions(from lines: [PerceptionTextRegion]) -> [PerceptionProductRegion] {
        let kept = lines.filter { !isPriceTag($0.text) && normalizeText($0.text).count >= 2 }
        return SignageService.blocks(kept).compactMap { block in
            guard let first = block.first else { return nil }
            let sorted = block.sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
            let text = sorted.map(\.text).joined(separator: " ")
            guard !isPriceTag(text) else { return nil }
            let box = block.dropFirst().reduce(first.box) { $0.union($1.box) }
            return PerceptionProductRegion(text: text, box: box, lines: sorted)
        }
    }

    /// The region under the pointed spot, else the nearest one within `maxDistance`.
    static func region(at p: NormPoint, in regions: [PerceptionProductRegion], maxDistance: Double = 0.08) -> PerceptionProductRegion? {
        let ranked = regions.map { ($0, $0.distance(to: p)) }.filter { $0.1 <= maxDistance }
        return ranked.min { ($0.1, $0.0.box.area) < ($1.1, $1.0.box.area) }?.0
    }
}
