import Foundation
import DigiFinderCore

/// Aisle signs ("Aisle 6: Coffee, Tea") and section signs ("Produce", "Checkout") from `.fast` text (§5.2, §5.6).
/// Groups text lines into blocks, then decides which blocks are signs; the rest are shelf labels (for the vote).
final class SignageService {
    /// Signs without the word "aisle" must sit in the upper part of the chest-height view (overhead / wall signs),
    /// so shelf labels saying "coffee" don't count as signs.
    static let sectionSignMaxY = 0.55
    static let destinationSignMaxY = 0.7
    static let maxSignWords = 10

    private let aisles: [String: AisleInfo]
    private let destinations: [Destination: [String]]
    private let synonyms: MatchingSynonyms

    init(aisles: [String: AisleInfo], destinations: [Destination: [String]], synonyms: MatchingSynonyms) {
        self.aisles = aisles; self.destinations = destinations; self.synonyms = synonyms
    }

    struct Result {
        var signs: [PerceptionSign] = []
        /// Text lines that aren't part of a sign and aren't price tags (shelf labels, product text).
        var labels: [PerceptionTextRegion] = []
    }

    func analyze(_ lines: [PerceptionTextRegion], goal: Goal?, geometry: PerceptionFrameGeometry) -> Result {
        var result = Result()
        for block in Self.blocks(lines) {
            if let sign = sign(from: block, goal: goal, geometry: geometry) {
                result.signs.append(sign)
            } else {
                result.labels += block.filter { !isPriceTag($0.text) }
            }
        }
        result.signs.sort { abs($0.degreesRight) < abs($1.degreesRight) }
        return result
    }

    // MARK: - Sign classification

    private func sign(from block: [PerceptionTextRegion], goal: Goal?, geometry: PerceptionFrameGeometry) -> PerceptionSign? {
        guard let first = block.first else { return nil }
        let box = block.dropFirst().reduce(first.box) { $0.union($1.box) }
        let text = block.map(\.text).joined(separator: " ")
        let norm = normalizeText(text)
        let tokens = norm.split(separator: " ").map(String.init)
        guard !tokens.isEmpty, tokens.count <= Self.maxSignWords * 2, !isPriceTag(text) else { return nil }

        let hasAisleWord = tokens.contains { $0.hasPrefix("aisle") }
        let destination = destinationForSign([text], destinations: destinations)
        let roughAisle = aisleForSign([text], catalog: aisles)
        let number = Self.aisleNumber(tokens, allowLone: hasAisleWord || (roughAisle != nil && destination == nil))
        let words = Self.signWords(block, dropping: number)
        let aisle = aisleForSign(words.isEmpty ? [text] : words, catalog: aisles)
        let goalHit = goal.map { !signMatchedTerms(words.isEmpty ? [text] : words, goal: $0, catalog: aisles, synonyms: synonyms).isEmpty } ?? false

        let isSign: Bool
        if hasAisleWord && (number != nil || aisle != nil) {
            isSign = true
        } else if destination != nil && box.midY <= Self.destinationSignMaxY && tokens.count <= Self.maxSignWords {
            isSign = true
        } else if (aisle != nil || goalHit) && box.midY <= Self.sectionSignMaxY && tokens.count <= Self.maxSignWords {
            isSign = true
        } else {
            isSign = false
        }
        guard isSign else { return nil }
        let clock = geometry.clock(box.midX)
        return PerceptionSign(sign: AisleSign(number: number, words: words, clock: clock), box: box,
                              degreesRight: geometry.degreesRight(box.midX), aisle: aisle, destination: destination,
                              lineHeight: block.map(\.box.height).max() ?? box.height, text: text)
    }

    /// "aisle 6" / "aisle6" / "aisle 12b"; else a lone 1–2 digit token (big aisle numbers often stand alone).
    static func aisleNumber(_ tokens: [String], allowLone: Bool) -> String? {
        func isNumberToken(_ t: String) -> Bool {
            let digits = t.prefix { $0.isNumber }
            let rest = t.dropFirst(digits.count)
            return (1...3).contains(digits.count) && rest.count <= 1 && rest.allSatisfy(\.isLetter)
        }
        for (i, t) in tokens.enumerated() {
            if t == "aisle" || t == "aisles", i + 1 < tokens.count, isNumberToken(tokens[i + 1]) { return tokens[i + 1].uppercased() }
            if t.hasPrefix("aisle"), t.count > 5 {
                let rest = String(t.dropFirst(5))
                if isNumberToken(rest) { return rest.uppercased() }
            }
        }
        guard allowLone else { return nil }
        let lone = tokens.filter { isNumberToken($0) && $0.first.map { $0 != "0" } == true }
        return lone.count == 1 ? lone[0].uppercased() : nil
    }

    /// The sign's phrases ("Coffee", "Tea"), without "Aisle" and the number.
    static func signWords(_ block: [PerceptionTextRegion], dropping number: String?) -> [String] {
        let separators = CharacterSet(charactersIn: ",&/|•·;:+")
        var out: [String] = []
        for line in block.sorted(by: { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }) {
            for part in line.text.components(separatedBy: separators) {
                for piece in part.components(separatedBy: " and ") {
                    var words = piece.split(separator: " ").map(String.init).filter { w in
                        let n = normalizeText(w)
                        if n == "aisle" || n == "aisles" || n.isEmpty { return false }
                        if let number, n == number.lowercased() || n == "aisle" + number.lowercased() { return false }
                        return true
                    }
                    words = words.filter { $0.contains { $0.isLetter } }
                    let phrase = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                    if phrase.count >= 2, !out.contains(phrase) { out.append(phrase) }
                }
            }
        }
        return out
    }

    // MARK: - Grouping

    /// Lines that sit together (stacked lines of one sign, or words on one row) form a block.
    static func blocks(_ lines: [PerceptionTextRegion]) -> [[PerceptionTextRegion]] {
        let n = lines.count
        guard n > 0 else { return [] }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in 0..<n {
            for j in (i + 1)..<n where together(lines[i].box, lines[j].box) {
                let a = find(i), b = find(j)
                if a != b { parent[b] = a }
            }
        }
        var groups: [Int: [PerceptionTextRegion]] = [:]
        var order: [Int] = []
        for i in 0..<n {
            let r = find(i)
            if groups[r] == nil { order.append(r) }
            groups[r, default: []].append(lines[i])
        }
        return order.compactMap { groups[$0] }
    }

    private static func together(_ a: NormRect, _ b: NormRect) -> Bool {
        let h = max(a.height, b.height)
        // Similar text size only (a big sign title and tiny label text don't merge).
        guard min(a.height, b.height) >= h * 0.4 else { return false }
        let vGap = max(0, max(a.y, b.y) - min(a.maxY, b.maxY))
        let hGap = max(0, max(a.x, b.x) - min(a.maxX, b.maxX))
        let hOverlap = hGap == 0
        let vOverlap = vGap == 0
        if hOverlap && vGap <= h * 1.2 { return true }          // stacked lines
        if vOverlap && hGap <= h * 1.5 { return true }          // same row
        return false
    }
}
