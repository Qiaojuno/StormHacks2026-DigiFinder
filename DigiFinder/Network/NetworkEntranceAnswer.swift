import Foundation
import DigiFinderCore

/// Gemini structured answer for the entrance pick (§9 Entrance pick). x values are 0 (left edge) ... 1000 (right edge).
struct NetworkEntranceAnswer: Decodable {
    let visible: Bool
    let x: Int?
    let kind: String?
    let cartCorralX: Int?
    let note: String?

    static var schema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "visible": ["type": "BOOLEAN"],
            "x": ["type": "INTEGER"],
            "kind": ["type": "STRING", "enum": ["automatic", "revolving", "push", "pull", "unknown"]],
            "cartCorralX": ["type": "INTEGER"],
            "note": ["type": "STRING"],
        ],
        "required": ["visible"],
    ] }

    /// nil = no entrance visible.
    var pick: EntrancePick? {
        guard visible, let x else { return nil }
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EntrancePick(x: Self.unit(x),
                            kind: DoorKind(rawValue: kind?.lowercased() ?? "") ?? .unknown,
                            cartCorralX: cartCorralX.map(Self.unit),
                            note: note?.isEmpty == false ? note : nil)
    }

    private static func unit(_ v: Int) -> Double { min(max(Double(v) / 1000, 0), 1) }
}
