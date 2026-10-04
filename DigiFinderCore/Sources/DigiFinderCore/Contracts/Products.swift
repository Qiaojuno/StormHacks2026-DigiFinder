// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

/// Goal fields come only from the user's words: brand/variant/form are set only if the user said them
/// (a brand counts when it matches a database brand). The database supplies the category and the candidates.
public struct Goal: Codable, Equatable {
    public var brand: String?
    public var product: String
    public var variant: [String]
    public var form: String?
    /// Aisle key; nil = unknown item (word search).
    public var category: String?
    public var synonyms: [String]
    /// Extra words to look for on signs (unknown items).
    public var signWords: [String]
    /// YOLO class the item itself looks like ("Mug", "Mobile phone", "Banana"), for finding it in view; nil = text only.
    public var visualClass: String?

    public init(brand: String? = nil, product: String, variant: [String] = [], form: String? = nil,
                category: String? = nil, synonyms: [String] = [], signWords: [String] = [], visualClass: String? = nil) {
        self.brand = brand; self.product = product; self.variant = variant; self.form = form
        self.category = category; self.synonyms = synonyms; self.signWords = signWords; self.visualClass = visualClass
    }
}

/// "actually X" / "also X" / bare "X".
public enum GoalChange: Equatable { case replace, add, unspecified }

public enum Destination: String, Codable { case customerService, checkout }

public struct ProductInfo: Codable, Equatable {
    public var code: String
    public var name: String
    public var brand: String?
    public var quantity: String?
    public var aisle: String?

    public init(code: String, name: String, brand: String? = nil, quantity: String? = nil, aisle: String? = nil) {
        self.code = code; self.name = name; self.brand = brand; self.quantity = quantity; self.aisle = aisle
    }
}

/// One entry of categories.json. Missing keys decode as empty lists.
public struct AisleInfo: Codable, Equatable {
    public var aisleWords: [String]
    public var productWords: [String]
    public var visualClasses: [String]
    public var adjacent: [String]
    public var offTags: [String]

    public init(aisleWords: [String] = [], productWords: [String] = [], visualClasses: [String] = [],
                adjacent: [String] = [], offTags: [String] = []) {
        self.aisleWords = aisleWords; self.productWords = productWords; self.visualClasses = visualClasses
        self.adjacent = adjacent; self.offTags = offTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aisleWords = try c.decodeIfPresent([String].self, forKey: .aisleWords) ?? []
        productWords = try c.decodeIfPresent([String].self, forKey: .productWords) ?? []
        visualClasses = try c.decodeIfPresent([String].self, forKey: .visualClasses) ?? []
        adjacent = try c.decodeIfPresent([String].self, forKey: .adjacent) ?? []
        offTags = try c.decodeIfPresent([String].self, forKey: .offTags) ?? []
    }
}
