import Foundation
import DigiFinderCore

/// Gemini structured answer for the assist call (§9 Ask): what to say, and an item to look for.
struct NetworkAssistAnswer: Decodable {
    let say: String
    let findItem: String?

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "say": ["type": "STRING"],
            "findItem": ["type": "STRING"],
        ],
        "required": ["say"],
    ] }
}

/// Gemini structured answer for the grocery check (app open).
struct NetworkPlaceAnswer: Decodable {
    let grocery: Bool?
    let confidence: Double?
    let scene: String?

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "grocery": ["type": "BOOLEAN"],
            "confidence": ["type": "NUMBER"],
            "scene": ["type": "STRING"],
        ],
        "required": ["grocery", "confidence", "scene"],
    ] }

    /// nil without a grocery answer; a missing confidence counts as 0 (unsure).
    var answer: PlaceAnswer? {
        guard let grocery else { return nil }
        let c = min(max(confidence ?? 0, 0), 1)
        return PlaceAnswer(grocery: grocery, confidence: c, scene: scene?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}
