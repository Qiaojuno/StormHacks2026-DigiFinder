import Foundation
import DigiFinderCore

/// Gemini REST `generateContent`: Ask and entrance pick only (§2 Network, §9 Ask / Entrance pick).
/// Structured JSON (responseSchema) → Codable. Header `x-goog-api-key`. ~6 s timeout. Stills must be upright JPEGs
/// (`NetworkJPEG.encode`).
struct GeminiRESTClient: GeminiClient {
    let apiKey: String
    let model: String

    static let timeout: TimeInterval = 6

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func ask(_ question: String, still: Data) async throws -> String {
        let prompt = """
            You help a blind shopper. The photo is from a camera on their chest. Question: "\(question)"
            Answer in at most 2 short spoken sentences. Only describe what is visible or printed.
            For dietary or allergen questions, end with "Check with staff to confirm."
            Do not give safety instructions or walking directions.
            """
        let a = try await generate(NetworkAskAnswer.self, prompt: prompt, images: [still],
                                   schema: NetworkAskAnswer.schema, timeout: Self.timeout)
        let answer = a.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw NetworkError.badResponse }
        return answer
    }

    /// nil = no entrance visible. `still` must be upright.
    func pickEntrance(still: Data) async throws -> EntrancePick? {
        let prompt = """
            This photo is from a camera on a blind shopper's chest, facing forward, outside a store.
            Is the store's main customer entrance visible? If unsure, visible = false.
            x: horizontal center of the entrance door, 0 = left edge of the photo, 1000 = right edge.
            kind: automatic, revolving, push, pull or unknown. cartCorralX: same scale, only if a cart corral is visible.
            note: at most 8 words the shopper should know at the door, or empty.
            """
        let a = try await generate(NetworkEntranceAnswer.self, prompt: prompt, images: [still],
                                   schema: NetworkEntranceAnswer.schema, timeout: Self.timeout)
        return a.pick
    }

    /// POST models/{model}:generateContent → decode candidates[0].content.parts[0].text as `T`.
    func generate<T: Decodable>(_ type: T.Type, prompt: String, images: [Data], schema: [String: Any],
                                timeout: TimeInterval) async throws -> T {
        guard !apiKey.isEmpty, let url = endpoint else { throw NetworkError.notConfigured }
        var parts: [[String: Any]] = [["text": prompt]]
        for jpeg in images {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "responseSchema": schema],
        ]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw NetworkError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw NetworkError.http(http.statusCode) }
        guard let envelope = try? JSONDecoder().decode(NetworkGeminiResponse.self, from: data),
              let json = envelope.jsonText?.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: json) else { throw NetworkError.badResponse }
        return value
    }

    private var endpoint: URL? {
        var name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("models/") { name.removeFirst("models/".count) }
        guard !name.isEmpty,
              let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):generateContent")
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
