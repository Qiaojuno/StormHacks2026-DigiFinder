// Wave 1 compiling stubs with the frozen Data API (§3.3). The Data agent replaces these (one file per type).
import CoreGraphics
import Foundation
import DigiFinderCore

/// products.sqlite (read-only, FTS5). nil if the file is missing.
final class ProductDatabase {
    init?(url: URL) { return nil }
    func search(_ text: String, limit: Int) -> [ProductInfo] { [] }
    func lookup(code: String) -> ProductInfo? { nil }
}

/// categories.json + synonyms.json. Missing files → empty aisles / no extras.
final class Catalog {
    let aisles: [String: AisleInfo]
    let destinations: [Destination: [String]]
    let extraProducts: [ProductInfo]

    init(aisles: [String: AisleInfo], destinations: [Destination: [String]], extraProducts: [ProductInfo]) {
        self.aisles = aisles; self.destinations = destinations; self.extraProducts = extraProducts
    }

    func aisle(forOffTags tags: [String]) -> String? { nil }

    static func load() -> Catalog { Catalog(aisles: [:], destinations: [:], extraProducts: []) }
}

/// Feature prints of confirmed products (§5.14). A hint only, never a confirmation.
final class ProductMemory {
    func save(_ p: ProductInfo, crop: CGImage) {}
    func hint(for crop: CGImage) -> ProductInfo? { nil }
}
