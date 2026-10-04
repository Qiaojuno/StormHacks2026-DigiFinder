import Foundation
import DigiFinderCore

/// Open Food Facts search for items missing from the offline database (§2 Network). Sends only the spoken words.
/// User-Agent `DigiFinder/0.1 (<OFFContact>)`, ~5 s timeout, at most 10 searches a minute (over the limit it throws
/// `NetworkError.rateLimited` without sending). Canada/US products (by barcode prefix) come first.
struct OpenFoodFactsClient: ProductLookupClient {
    let contact: String?

    static let timeout: TimeInterval = 5
    static let limiter = NetworkRateLimiter(limit: 10, window: 60)

    init(contact: String?) {
        self.contact = contact
    }

    func search(_ words: String) async throws -> [OnlineProduct] {
        let terms = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return [] }
        guard let url = Self.searchURL(terms) else { throw NetworkError.badResponse }
        guard Self.limiter.tryAcquire() else { throw NetworkError.rateLimited }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw NetworkError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        if http.statusCode == 429 { throw NetworkError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw NetworkError.http(http.statusCode) }
        guard let decoded = try? JSONDecoder().decode(NetworkOFFResponse.self, from: data) else {
            throw NetworkError.badResponse
        }
        let mapped = (decoded.products ?? []).compactMap(Self.map)
        // Stable: Canada/US hits first, otherwise the server's order.
        return mapped.enumerated()
            .sorted { a, b in
                let na = Self.isNorthAmerican(a.element.info.code), nb = Self.isNorthAmerican(b.element.info.code)
                return na != nb ? na : a.offset < b.offset
            }
            .map(\.element)
    }

    var userAgent: String {
        let c = contact?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "DigiFinder/0.1 (\(c.isEmpty ? "no contact set" : c))"
    }

    static func searchURL(_ words: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let q = words.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1"
                   + "&action=process&json=1&page_size=5&fields=code,product_name,brands,quantity,categories_tags")
    }

    /// UPC-A (12 digits) and GS1 prefixes 000–139 (US and Canada) or 754–755 (Canada).
    static func isNorthAmerican(_ code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        guard digits.count == code.count else { return false }
        if digits.count == 12 { return true }
        guard digits.count == 13, let prefix = Int(digits.prefix(3)) else { return false }
        return prefix <= 139 || prefix == 754 || prefix == 755
    }

    private static func map(_ p: NetworkOFFResponse.Product) -> OnlineProduct? {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        guard let name = clean(p.productName) else { return nil }
        let brand = clean(p.brands?.split(separator: ",").first.map(String.init))
        let info = ProductInfo(code: clean(p.code) ?? "", name: name, brand: brand, quantity: clean(p.quantity), aisle: nil)
        return OnlineProduct(info: info, categoryTags: p.categoriesTags ?? [])
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        c.waitsForConnectivity = false
        c.urlCache = nil
        return URLSession(configuration: c)
    }()
}
