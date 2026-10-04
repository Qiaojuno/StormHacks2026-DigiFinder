import Foundation
import DigiFinderCore

/// Store knowledge from the bundle (§7.2): `categories.json` (generated aisles) + `synonyms.json` (hand-edited).
/// Either file may be missing or unreadable: no categories → empty aisles (word search only);
/// no synonyms → no destinations, synonyms or extra products.
final class Catalog {
    let aisles: [String: AisleInfo]
    /// Sign and request words per destination, in `normalizeText` form.
    let destinations: [Destination: [String]]
    /// Hand-added products (store brands, demo items missing from the database).
    let extraProducts: [ProductInfo]
    /// `synonyms.json` "synonyms", in `normalizeText` form: canonical phrase → other ways to say it.
    let synonyms: [String: [String]]

    init(aisles: [String: AisleInfo], destinations: [Destination: [String]], extraProducts: [ProductInfo],
         synonyms: [String: [String]] = [:]) {
        self.aisles = aisles; self.destinations = destinations; self.extraProducts = extraProducts
        self.synonyms = synonyms
    }

    /// Maps Open Food Facts category tags (online lookup) to an aisle key, or nil.
    /// The aisle owning the most specific matching tag wins (OFF lists tags from general to specific),
    /// then the aisle with more matching tags, then the alphabetically first key.
    func aisle(forOffTags tags: [String]) -> String? {
        let wanted = tags.map(Self.offTag)
        var best: (key: String, specific: Int, matches: Int)?
        for (key, info) in aisles {
            let own = Set(info.offTags.map(Self.offTag))
            var specific = -1, matches = 0
            for (i, tag) in wanted.enumerated() where own.contains(tag) { specific = i; matches += 1 }
            guard matches > 0 else { continue }
            if let b = best, (b.specific, b.matches) > (specific, matches) { continue }
            if let b = best, (b.specific, b.matches) == (specific, matches), b.key < key { continue }
            best = (key, specific, matches)
        }
        return best?.key
    }

    static func load() -> Catalog {
        load(categoriesURL: Bundle.main.url(forResource: "categories", withExtension: "json"),
             synonymsURL: Bundle.main.url(forResource: "synonyms", withExtension: "json"))
    }

    /// Loads from explicit files (tests); nil or unreadable files count as missing.
    static func load(categoriesURL: URL?, synonymsURL: URL?) -> Catalog {
        let aisles = categoriesURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: AisleInfo].self, from: $0) } ?? [:]
        let file = synonymsURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(CatalogSynonymsFile.self, from: $0) }

        var destinations: [Destination: [String]] = [:]
        for (raw, words) in file?.destinations ?? [:] {
            guard let d = Destination(rawValue: raw) else { continue }
            destinations[d] = normalizedList(words)
        }
        var synonyms: [String: [String]] = [:]
        for (canonical, aliases) in file?.synonyms ?? [:] {
            let key = normalizeText(canonical)
            guard !key.isEmpty else { continue }
            synonyms[key, default: []] += normalizedList(aliases).filter { $0 != key }
        }
        let extras: [ProductInfo] = (file?.extraProducts ?? []).compactMap { e in
            guard let name = e.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            func clean(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
                return t
            }
            return ProductInfo(code: normalizeBarcode(e.code ?? ""), name: name, brand: clean(e.brand),
                               quantity: clean(e.quantity), aisle: clean(e.aisle))
        }
        return Catalog(aisles: aisles, destinations: destinations, extraProducts: extras, synonyms: synonyms)
    }

    private static func normalizedList(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.map(normalizeText).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func offTag(_ tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
        return t.contains(":") ? t : "en:" + t
    }
}

/// `synonyms.json`. Each top-level key is read on its own, so one bad key doesn't lose the others.
private struct CatalogSynonymsFile: Decodable {
    var synonyms: [String: [String]]?
    var destinations: [String: [String]]?
    var extraProducts: [CatalogExtraProduct]?

    enum CodingKeys: String, CodingKey { case synonyms, destinations, extraProducts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        synonyms = try? c.decodeIfPresent([String: [String]].self, forKey: .synonyms)
        destinations = try? c.decodeIfPresent([String: [String]].self, forKey: .destinations)
        extraProducts = try? c.decodeIfPresent([CatalogExtraProduct].self, forKey: .extraProducts)
    }
}

/// One `extraProducts` entry; every field optional ("code" is often empty for store brands).
private struct CatalogExtraProduct: Decodable {
    var code: String?, name: String?, brand: String?, quantity: String?, aisle: String?
}
