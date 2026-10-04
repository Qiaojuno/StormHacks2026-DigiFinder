import Foundation
import DigiFinderCore

/// Pointed product (§5.2 user points): product region under the fingertip scored against the goal candidates,
/// direction to the best-matching region, size alternative, and the memory hint (§5.14, never final).
struct PerceptionPointingAnalyzer {
    var synonyms: MatchingSynonyms
    /// Coverage at which a region's text is taken as a specific candidate (for its spoken name and size).
    var identifyCoverage = 0.6

    struct Result {
        var pointed: PointedProduct?
        var pointedRegion: PerceptionProductRegion?
        var target: PerceptionProductRegion?
    }

    func analyze(spot: NormPoint, regions: [PerceptionProductRegion], goal: Goal?, candidates: [ProductInfo],
                 wordSearch: Bool, hint: ProductInfo?) -> Result {
        let scored = regions.map { ($0, match($0.text, goal: goal, candidates: candidates, wordSearch: wordSearch)) }
        let under = ProductRegions.region(at: spot, in: regions)
        let target = scored.filter { $0.1 >= MatchingThresholds.pointMatch }
            .min { $0.0.distance(to: spot) < $1.0.distance(to: spot) }?.0

        guard let region = under else {
            // Nothing readable at the fingertip: steer toward the target if it's in view.
            guard let t = target, let dir = Geometry.pointingDirection(from: spot, to: t.box) else {
                return Result(pointed: nil, pointedRegion: nil, target: target)
            }
            return Result(pointed: PointedProduct(text: "", match: 0, directionToTarget: dir), pointedRegion: nil, target: target)
        }

        var m = scored.first { $0.0 == region }?.1 ?? 0
        var product = identify(region.text, candidates: candidates)
        if m < MatchingThresholds.pointMatch, let h = hint, isGoalProduct(h, goal: goal, candidates: candidates) {
            // Memory says this looks like the goal; the hold-up label check still decides.
            m = MatchingThresholds.pointMatch
            product = h
        }
        let text = product.map { spokenProduct($0) } ?? Self.readable(region.text)
        var direction: String?
        if m < MatchingThresholds.pointMatch, let t = target, t != region {
            direction = Geometry.pointingDirection(from: spot, to: t.box)
        }
        var alternative: String?
        if m >= MatchingThresholds.pointMatch, let p = product {
            alternative = variantAlternativeLine(current: p, candidates: candidates)
        }
        return Result(pointed: PointedProduct(text: text, match: m, directionToTarget: direction, alternative: alternative),
                      pointedRegion: region, target: target)
    }

    func match(_ text: String, goal: Goal?, candidates: [ProductInfo], wordSearch: Bool) -> Double {
        guard let goal else { return 0 }
        if wordSearch { return wordSearchLabelMatches(text, goal: goal, synonyms: synonyms) ? 1 : 0 }
        return score(text, goal, candidates: candidates, synonyms: synonyms)
    }

    func identify(_ text: String, candidates: [ProductInfo]) -> ProductInfo? {
        guard let (p, coverage) = confirmFromLabel(text, candidates: candidates), coverage >= identifyCoverage else { return nil }
        return p
    }

    func isGoalProduct(_ p: ProductInfo, goal: Goal?, candidates: [ProductInfo]) -> Bool {
        if candidates.contains(p) { return true }
        if !p.code.isEmpty, candidates.contains(where: { normalizeBarcode($0.code) == normalizeBarcode(p.code) }) { return true }
        guard let goal else { return false }
        return score("\(p.brand ?? "") \(p.name)", goal, candidates: [], synonyms: synonyms) >= MatchingThresholds.pointMatch
    }

    /// First few words of OCR text, for "That's <text>."
    static func readable(_ text: String, maxWords: Int = 6) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).prefix(maxWords).joined(separator: " ")
    }
}
