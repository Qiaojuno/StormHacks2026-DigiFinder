import Foundation
import DigiFinderCore

/// Gemini REST `generateContent`: assist (Ask), entrance pick, the grocery check and the item finder only
/// (§2 Network, §9).
/// Structured JSON (responseSchema) → Codable. Header `x-goog-api-key`. ~6 s timeout. Stills must be upright JPEGs
/// (`NetworkJPEG.encode`).
struct GeminiRESTClient: GeminiClient {
    /// Main key first, then the fallback.
    let apiKeys: [String]
    let model: String
    private let keys: NetworkKeyChooser

    /// Photo requests can take several seconds under load; 10 s avoids discarding slow but valid answers.
    static let timeout: TimeInterval = 10

    init(apiKey: String, model: String) { self.init(apiKeys: [apiKey], model: model) }

    init(apiKeys: [String], model: String) {
        self.apiKeys = apiKeys.filter { !$0.isEmpty }
        self.model = model
        keys = NetworkKeyChooser(count: self.apiKeys.count)
    }

    /// Anything the offline router couldn't handle: a question, an unknown item, or words it couldn't place.
    func assist(_ transcript: String, context: AssistContext, still: Data) async throws -> GeminiAssist {
        let place: String
        switch context.store {
        case true?: place = "inside a grocery store"
        case false?: place = "not in a store (home, office or similar)"
        case nil: place = "unknown"
        }
        let goal = context.goal.map { "\"\($0)\"" } ?? "none"
        let prompt = """
            You help a blind shopper through a phone camera on their chest. They said: "\(transcript)"
            Place: \(place). Currently looking for: \(goal). Step: \(context.phase.title).
            say: your spoken reply, at most 2 short sentences. Only describe what is visible or printed, or answer
            plainly. For dietary or allergen questions, end with "Check with staff to confirm."
            Never give safety instructions or walking directions.
            findItem: only if they want to find or buy something, the thing to look for in 1 to 4 words
            (for example "oat milk" or "car keys"); otherwise leave it empty.
            """
        let a = try await generate(NetworkAssistAnswer.self, prompt: prompt, images: [still],
                                   schema: NetworkAssistAnswer.schema, timeout: Self.timeout)
        let say = a.say.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = a.findItem?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !say.isEmpty || item?.isEmpty == false else { throw NetworkError.badResponse }
        return GeminiAssist(say: say, findItem: item?.isEmpty == false ? item : nil)
    }

    /// Item finder (while searching, ~every 2 s): is the goal in this photo (latest Stream B frame, upright)?
    func findItem(_ description: String, image: Data) async throws -> ItemFinding? {
        let prompt = """
            This photo is from a camera on a blind person's chest. Find: \(description). \
            If it is visible, give its bounding box as box_2d [ymin, xmin, ymax, xmax] on a 0–1000 scale, your \
            confidence 0–1, and a 3–6 word description of what you see. If it is not visible, set found false and \
            give one short hint (at most 12 words) about where it is likely to be relative to this photo, using \
            clock positions (12 = straight ahead, 3 = right, 9 = left), or an empty hint.
            """
        let a = try await generate(NetworkItemAnswer.self, prompt: prompt, images: [image],
                                   schema: NetworkItemAnswer.schema, timeout: Self.timeout)
        return a.finding
    }

    /// Grocery store or anywhere else, from 3 stills in one request (once at app open). nil = no usable answer.
    func classifyPlace(stills: [Data]) async throws -> PlaceAnswer? {
        guard !stills.isEmpty else { return nil }
        let prompt = """
            These photos are from a camera on a blind person's chest. Is this inside a grocery store or supermarket \
            (aisles of food products, shelves, price tags)? Anywhere else — home, office, campus, library, school, \
            outdoors, another kind of shop — is false. Give your confidence 0–1 and a 2–4 word scene description.
            """
        let a = try await generate(NetworkPlaceAnswer.self, prompt: prompt, images: stills,
                                   schema: NetworkPlaceAnswer.schema, timeout: Self.timeout)
        return a.answer
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
        guard !apiKeys.isEmpty, let url = endpoint else { throw NetworkError.notConfigured }
        var parts: [[String: Any]] = [["text": prompt]]
        for jpeg in images {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            // Low thinking: a small structured answer in ~2.3 s (live test with gemini-3.8-flash).
            "generationConfig": ["responseMimeType": "application/json", "responseSchema": schema,
                                 "thinkingConfig": ["thinkingLevel": "low"]],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        // Main key first; a refused key (401/402/403/429: API disabled, no credit, blocked, quota) falls back to the
        // other key for the same request, and the working key is preferred for later requests.
        var data = Data()
        var lastStatus = 0
        for index in keys.order() {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKeys[index], forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = payload
            let response: URLResponse
            do {
                (data, response) = try await Self.session.data(for: request)
            } catch {
                throw NetworkError.from(error)
            }
            guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
            lastStatus = http.statusCode
            if (200..<300).contains(http.statusCode) {
                keys.worked(index)
                break
            }
            guard NetworkKeyChooser.refused.contains(http.statusCode) else { throw NetworkError.http(http.statusCode) }
            keys.refused(index)
        }
        guard (200..<300).contains(lastStatus) else { throw NetworkError.http(lastStatus) }
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
