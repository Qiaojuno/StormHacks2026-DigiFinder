import Foundation

/// Gemini structured answer for the held-item check (owner decision: the search ends only when the user holds the
/// right item).
struct NetworkHeldAnswer: Decodable {
    let holding: Bool?
    let isGoal: Bool?
    let name: String?

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "holding": ["type": "BOOLEAN"],
            "isGoal": ["type": "BOOLEAN"],
            "name": ["type": "STRING"],
        ],
        "required": ["holding", "isGoal", "name"],
    ] }

    var check: HeldCheck {
        let holding = holding ?? false
        let words = (name ?? "").split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
        return HeldCheck(holding: holding, isGoal: holding && (isGoal ?? false), name: words)
    }
}
