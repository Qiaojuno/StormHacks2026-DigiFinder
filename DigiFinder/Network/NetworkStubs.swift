// Wave 1 compiling stubs. The Voice-Feedback-Network-System agent replaces these (one file per type).
import Foundation
import DigiFinderCore

enum NetworkError: Error { case notConfigured, offline, badResponse, timeout }

/// Gemini REST generateContent: Ask and entrance pick only (§2 Network).
struct GeminiRESTClient: GeminiClient {
    let apiKey: String
    let model: String

    func ask(_ question: String, still: Data) async throws -> String { throw NetworkError.notConfigured }
    func pickEntrance(still: Data) async throws -> EntrancePick? { nil }
}

/// Open Food Facts search for items missing from the offline database. Sends only the spoken words.
struct OpenFoodFactsClient: ProductLookupClient {
    let contact: String?

    func search(_ words: String) async throws -> [OnlineProduct] { [] }
}
