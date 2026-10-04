import Foundation

/// The parts of a `generateContent` response we read: candidates[0].content.parts[].text.
struct NetworkGeminiResponse: Decodable {
    struct Part: Decodable { let text: String?; let thought: Bool? }
    struct Content: Decodable { let parts: [Part]? }
    struct Candidate: Decodable { let content: Content? }

    let candidates: [Candidate]?

    /// The JSON text of the first candidate (thought parts skipped, code fences stripped).
    var jsonText: String? {
        guard let parts = candidates?.first?.content?.parts else { return nil }
        let text = parts.filter { $0.thought != true }.compactMap(\.text).joined()
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t.isEmpty ? nil : t
    }
}
