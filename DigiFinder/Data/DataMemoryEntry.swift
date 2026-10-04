import Foundation
import DigiFinderCore

/// One remembered product on disk (§5.14): what was confirmed, plus 1–5 feature prints of its label crop.
struct DataMemoryEntry: Codable {
    /// Code, name, brand, quantity, aisle as confirmed.
    var product: ProductInfo
    /// Archived `VNFeaturePrintObservation`s (NSKeyedArchiver), oldest first.
    var prints: [Data]
    /// `VNGenerateImageFeaturePrintRequest` revision that made the prints; other revisions can't be compared.
    var revision: Int
    /// Last confirmation; the oldest entries go first when the cap is reached.
    var updated: Date
}
