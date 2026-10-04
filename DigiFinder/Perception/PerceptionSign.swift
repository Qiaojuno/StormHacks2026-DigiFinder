import Foundation
import DigiFinderCore

/// One aisle or section sign seen on Stream B, with where it is.
struct PerceptionSign: Equatable {
    var sign: AisleSign
    var box: NormRect
    /// Horizontal angle right of ahead (degrees).
    var degreesRight: Double
    /// Aisle key the sign names (categories.json), if any.
    var aisle: String?
    /// Destination the sign names, if any.
    var destination: Destination?
    /// Tallest text line on the sign (normalized portrait height), for a size-based distance estimate.
    var lineHeight: Double
    /// All of the sign's text, joined.
    var text: String

    /// Identity across frames: the number, else the words.
    var key: String { sign.number.map { "aisle \($0)" } ?? normalizeText(sign.words.joined(separator: " ")) }
}
