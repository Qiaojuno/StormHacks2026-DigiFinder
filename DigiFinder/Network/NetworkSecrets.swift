import Foundation

/// Keys from Resources/Secrets.plist (gitignored), read at runtime. Missing file or keys → online extras off.
struct NetworkSecrets {
    var geminiAPIKey: String?
    var geminiModel: String?
    var offContact: String?

    var hasGemini: Bool { geminiAPIKey != nil && geminiModel != nil }

    static func load(bundle: Bundle = .main) -> NetworkSecrets {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return NetworkSecrets() }
        func value(_ key: String) -> String? {
            guard let s = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, !s.hasPrefix("YOUR_") else { return nil }
            return s
        }
        return NetworkSecrets(geminiAPIKey: value("GeminiAPIKey"), geminiModel: value("GeminiModel"),
                              offContact: value("OFFContact"))
    }
}
