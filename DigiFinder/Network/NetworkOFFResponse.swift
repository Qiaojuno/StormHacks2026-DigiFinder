import Foundation

/// Open Food Facts search response (fields=code,product_name,brands,quantity,categories_tags).
struct NetworkOFFResponse: Decodable {
    struct Product: Decodable {
        let code: String?
        let productName: String?
        let brands: String?
        let quantity: String?
        let categoriesTags: [String]?

        enum CodingKeys: String, CodingKey {
            case code, brands, quantity
            case productName = "product_name"
            case categoriesTags = "categories_tags"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // `code` is usually a string but has been seen as a number.
            if let s = try? c.decode(String.self, forKey: .code) {
                code = s
            } else if let n = try? c.decode(Int64.self, forKey: .code) {
                code = String(n)
            } else {
                code = nil
            }
            productName = try? c.decode(String.self, forKey: .productName)
            brands = try? c.decode(String.self, forKey: .brands)
            quantity = try? c.decode(String.self, forKey: .quantity)
            categoriesTags = try? c.decode([String].self, forKey: .categoriesTags)
        }
    }

    let products: [Product]?
}
