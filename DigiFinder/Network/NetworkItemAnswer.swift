import Foundation
import DigiFinderCore

/// Gemini structured answer for the item finder: is the goal item in this photo, where, or where to look.
struct NetworkItemAnswer: Decodable {
    let found: Bool?
    /// [ymin, xmin, ymax, xmax] on a 0–1000 scale of the upright photo.
    let box_2d: [Double]?
    let confidence: Double?
    let description: String?
    let hint: String?

    /// Below this Gemini's "found" counts as not found.
    static let minConfidence = 0.5
    static let maxHintWords = 12

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "found": ["type": "BOOLEAN"],
            "box_2d": ["type": "ARRAY", "items": ["type": "INTEGER"]],
            "confidence": ["type": "NUMBER"],
            "description": ["type": "STRING"],
            "hint": ["type": "STRING"],
        ],
        "required": ["found", "confidence", "description", "hint"],
    ] }

    /// nil without a found flag.
    var finding: ItemFinding? {
        guard let found else { return nil }
        let c = min(max(confidence ?? 0, 0), 1)
        let box = box_2d.flatMap(Self.rect)
        let ok = found && c >= Self.minConfidence && box != nil
        let words = (hint ?? "").split(whereSeparator: \.isWhitespace).prefix(Self.maxHintWords)
        return ItemFinding(found: ok, box: ok ? box : nil, confidence: c,
                           description: description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                           hint: ok ? "" : words.joined(separator: " "))
    }

    /// box_2d → contract-space rect (x = xmin/1000, y = ymin/1000, …); nil when degenerate.
    static func rect(_ b: [Double]) -> NormRect? {
        guard b.count == 4 else { return nil }
        let v = b.map { min(max($0 / 1000, 0), 1) }
        let (ymin, xmin, ymax, xmax) = (min(v[0], v[2]), min(v[1], v[3]), max(v[0], v[2]), max(v[1], v[3]))
        guard xmax - xmin >= 0.01, ymax - ymin >= 0.01 else { return nil }
        return NormRect(x: xmin, y: ymin, width: xmax - xmin, height: ymax - ymin)
    }
}
