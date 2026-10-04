import Foundation

/// Keys from Resources/Secrets.plist (gitignored), read at runtime. Missing file or keys → online extras off.
struct NetworkSecrets {
    var geminiAPIKey: String?
    /// Used when the main key is refused (disabled API, no credit, blocked, out of quota).
    var geminiFallbackAPIKey: String?
    var geminiModel: String?
    var offContact: String?

    /// Main key first, then the fallback (either may be missing).
    var geminiKeys: [String] { [geminiAPIKey, geminiFallbackAPIKey].compactMap { $0 } }
    var hasGemini: Bool { !geminiKeys.isEmpty && geminiModel != nil }

    static func load(bundle: Bundle = .main) -> NetworkSecrets {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return NetworkSecrets() }
        func value(_ key: String) -> String? {
            guard let s = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, !s.hasPrefix("YOUR_") else { return nil }
            return s
        }
        return NetworkSecrets(geminiAPIKey: value("GeminiAPIKey"), geminiFallbackAPIKey: value("GeminiFallbackAPIKey"),
                              geminiModel: value("GeminiModel"), offContact: value("OFFContact"))
    }
}
