import AVFoundation
import Foundation

/// English voice choice: Premium → Enhanced → default (§2 Audio and input).
enum FeedbackVoicePicker {
    static func bestEnglishVoice(language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exact = voices.filter { $0.language == language }
        let english = voices.filter { $0.language.hasPrefix("en") }
        for pool in [exact, english] {
            if let v = pool.first(where: { $0.quality == .premium }) { return v }
            if let v = pool.first(where: { $0.quality == .enhanced }) { return v }
        }
        return AVSpeechSynthesisVoice(language: language) ?? exact.first ?? english.first
    }
}
