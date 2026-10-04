import CoreGraphics
import Foundation
import Vision
import DigiFinderCore

/// Held-item check (§5.2 grab and check): full-res still → `.accurate` text + passive barcode → candidates, then the
/// database for wrong items. A visible barcode wins. Use from one queue at a time (requests are reused).
final class PerceptionLabelChecker {
    struct Outcome {
        var product: ProductInfo
        var isGoal: Bool
        /// Upright crop of the label (for product memory).
        var crop: CGImage?
    }

    private let text = TextRecognitionService(level: .accurate)
    private let barcodes = BarcodeService()
    private let products: ProductDatabase?
    private let extraProducts: [ProductInfo]
    private let pointing: PerceptionPointingAnalyzer

    /// Text and codes from the last check (debug overlay).
    private(set) var lastLines: [PerceptionTextRegion] = []
    private(set) var lastBarcode: String?

    init(products: ProductDatabase?, extraProducts: [ProductInfo], synonyms: MatchingSynonyms) {
        self.products = products
        self.extraProducts = extraProducts
        pointing = PerceptionPointingAnalyzer(synonyms: synonyms)
        text.minConfidence = 0.2
    }

    /// nil = unclear (nothing identified with enough confidence).
    func check(_ still: CGImage, goal: Goal?, candidates: [ProductInfo], wordSearch: Bool, barcodesOn: Bool = true) -> Outcome? {
        let handler = VNImageRequestHandler(cgImage: still, orientation: .up, options: [:])
        text.setRegion(nil)
        var requests: [VNRequest] = [text.request]
        if barcodesOn { requests.append(barcodes.request) }
        do { try handler.perform(requests) } catch { return nil }
        let lines = text.results().sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
        let code = barcodesOn ? barcodes.results().first : nil
        lastLines = lines
        lastBarcode = code
        let label = lines.map(\.text).joined(separator: " ")
        let crop = labelCrop(still, lines: lines)

        // 1. A visible barcode wins.
        if let code {
            if let p = confirmFromBarcode(code, candidates: candidates) { return Outcome(product: p, isGoal: true, crop: crop) }
            if let p = lookup(code: code) {
                return Outcome(product: p, isGoal: pointing.isGoalProduct(p, goal: goal, candidates: candidates), crop: crop)
            }
        }
        guard !normalizeText(label).isEmpty else { return nil }

        // 2. Word search: the spoken words on the label; read it back ("This says Cedar's tahini.").
        if wordSearch, let goal {
            if wordSearchLabelMatches(label, goal: goal, synonyms: pointing.synonyms) {
                let name = PerceptionPointingAnalyzer.readable(prominentText(lines))
                return Outcome(product: ProductInfo(code: code ?? "", name: name), isGoal: true, crop: crop)
            }
            return nil
        }

        // 3. Goal candidates by label words (brand, name, size).
        if let (p, coverage) = confirmFromLabel(label, candidates: candidates), coverage >= MatchingThresholds.confirm {
            return Outcome(product: p, isGoal: true, crop: crop)
        }

        // 4. Something else: look the label up to name the wrong item ("That's ground, not whole bean.").
        let others = searchDatabase(lines)
        if let (p, coverage) = confirmFromLabel(label, candidates: others), coverage >= MatchingThresholds.confirm {
            return Outcome(product: p, isGoal: pointing.isGoalProduct(p, goal: goal, candidates: candidates), crop: crop)
        }
        return nil
    }

    private func lookup(code: String) -> ProductInfo? {
        if let p = products?.lookup(code: code) { return p }
        return extraProducts.first { !$0.code.isEmpty && normalizeBarcode($0.code) == code }
    }

    /// Products named by the label's largest words (brand and name are usually the biggest text).
    private func searchDatabase(_ lines: [PerceptionTextRegion]) -> [ProductInfo] {
        var words: [String] = []
        for line in lines.sorted(by: { $0.box.height > $1.box.height }).prefix(4) {
            for w in normalizedWords(line.text) where w.count >= 3 && !w.allSatisfy(\.isNumber) && !words.contains(w) {
                words.append(w)
            }
        }
        guard !words.isEmpty else { return extraProducts }
        var found: [ProductInfo] = []
        if let db = products {
            for n in stride(from: min(words.count, 3), through: 1, by: -1) {
                found = db.search(words.prefix(n).joined(separator: " "), limit: 25)
                if !found.isEmpty { break }
            }
        }
        return found + extraProducts
    }

    /// The tallest lines, in reading order.
    private func prominentText(_ lines: [PerceptionTextRegion]) -> String {
        guard let tallest = lines.map(\.box.height).max() else { return "" }
        return lines.filter { $0.box.height >= tallest * 0.6 }.map(\.text).joined(separator: " ")
    }

    private func labelCrop(_ still: CGImage, lines: [PerceptionTextRegion]) -> CGImage? {
        guard let first = lines.first else {
            return PerceptionImageTools.crop(still, rect: NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), pad: 0)
        }
        let box = lines.dropFirst().reduce(first.box) { $0.union($1.box) }
        return PerceptionImageTools.crop(still, rect: box, pad: 0.03)
    }
}
