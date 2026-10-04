import Foundation

/// Gemini structured answer for Ask (§9 Ask).
struct NetworkAskAnswer: Decodable {
    let answer: String

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": ["answer": ["type": "STRING"]],
        "required": ["answer"],
    ] }
}
