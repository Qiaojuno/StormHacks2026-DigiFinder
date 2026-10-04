import AVFoundation
import Foundation
import Observation
import DigiFinderCore

/// Spoken speed choices (§5.13). `rate` is on the `AVSpeechUtterance.rate` scale (default 0.5).
enum UISpeechSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast, faster

    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .faster: return "Faster"
        }
    }
    var rate: Float {
        switch self {
        case .slow: return 0.42
        case .normal: return 0.5
        case .fast: return 0.56
        case .faster: return 0.62
        }
    }
}

/// How distances are spoken (§5.13).
enum UIDistanceUnits: String, Codable, CaseIterable, Identifiable {
    case meters, steps

    var id: String { rawValue }
    var title: String { self == .meters ? "Meters" : "Steps" }
}

/// User settings from the setup sheet (§5.13). The runner applies them (see `UISessionDriving.apply(settings:)`).
struct UISettings: Codable, Equatable {
    var speechSpeed: UISpeechSpeed = .normal
    /// `AVSpeechSynthesisVoice.identifier`; nil = best English voice (Premium → Enhanced → default).
    var voiceIdentifier: String?
    var units: UIDistanceUnits = .meters
    /// Listening beep, done chime, scan ticks.
    var tonesEnabled = true
    /// Danger vibrations. On by default; the only thing that vibrates.
    var dangerHapticsEnabled = true
    var detail: Verbosity = .normal
    var hasHeardWalkthrough = false
    /// Nearby mode: look around for the item itself (home, a room), no signs or aisles.
    var nearbyMode = false

    init() {}

    // Tolerant decoding: a missing or unknown field falls back to its default instead of losing every setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UISettings()
        speechSpeed = (try? c.decodeIfPresent(UISpeechSpeed.self, forKey: .speechSpeed)) ?? d.speechSpeed
        voiceIdentifier = (try? c.decodeIfPresent(String.self, forKey: .voiceIdentifier)) ?? nil
        units = (try? c.decodeIfPresent(UIDistanceUnits.self, forKey: .units)) ?? d.units
        tonesEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .tonesEnabled)) ?? d.tonesEnabled
        dangerHapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .dangerHapticsEnabled)) ?? d.dangerHapticsEnabled
        detail = (try? c.decodeIfPresent(Verbosity.self, forKey: .detail)) ?? d.detail
        hasHeardWalkthrough = (try? c.decodeIfPresent(Bool.self, forKey: .hasHeardWalkthrough)) ?? d.hasHeardWalkthrough
        nearbyMode = (try? c.decodeIfPresent(Bool.self, forKey: .nearbyMode)) ?? d.nearbyMode
    }
}

extension Verbosity {
    /// Detail levels in setup order (no protocol conformances added to the Core type).
    static var uiChoices: [Verbosity] { [.brief, .normal, .detailed] }
    var uiTitle: String {
        switch self {
        case .brief: return "Brief"
        case .normal: return "Normal"
        case .detailed: return "Detailed"
        }
    }
}

/// One English voice choice for the setup sheet.
struct UIVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String

    /// English voices installed on the device, best quality first.
    static func englishVoices() -> [UIVoiceOption] {
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 0
            case .enhanced: return 1
            default: return 2
            }
        }
        func qualityName(_ q: AVSpeechSynthesisVoiceQuality) -> String {
            switch q {
            case .premium: return ", premium"
            case .enhanced: return ", enhanced"
            default: return ""
            }
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { (rank($0.quality), $0.name, $0.language) < (rank($1.quality), $1.name, $1.language) }
            .map { UIVoiceOption(id: $0.identifier, name: "\($0.name) (\($0.language))\(qualityName($0.quality))") }
    }
}

/// Persists `UISettings` in UserDefaults as JSON. Every read and write is failure-tolerant:
/// unreadable data falls back to the defaults, a failed encode keeps the last saved value.
@Observable @MainActor
final class UISettingsStore {
    var settings: UISettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange?(settings)
        }
    }

    @ObservationIgnored var onChange: ((UISettings) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults? = .standard, key: String = "DigiFinder.settings.v1") {
        self.defaults = defaults
        self.key = key
        settings = Self.load(defaults: defaults, key: key)
    }

    private static func load(defaults: UserDefaults?, key: String) -> UISettings {
        guard let data = defaults?.data(forKey: key),
              let decoded = try? JSONDecoder().decode(UISettings.self, from: data) else { return UISettings() }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }
}
