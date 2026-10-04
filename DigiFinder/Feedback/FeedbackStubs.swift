// Wave 1 compiling stubs. The Voice-Feedback-Network-System agent replaces these (one file per type).
import Foundation
import DigiFinderCore

/// AVSpeechSynthesizer + speech priority queue + VoiceOver announcements (§5.15); haptics first on danger.
final class SpeechFeedback: FeedbackOutput {
    private let haptics: HapticsService
    private let tones: ToneService

    init(haptics: HapticsService, tones: ToneService) {
        self.haptics = haptics; self.tones = tones
    }

    var isSpeaking: Bool { false }
    func danger(_ label: String, steer: Steer) {}
    func say(_ text: String, _ p: SpeechPriority) {}
    func stopSpeech() {}
    func chime(_ t: Tone) {}
}

/// Core Haptics danger pattern (2–3 strong ~150 ms pulses). Danger only.
final class HapticsService {
    func dangerPulse() {}
}

/// Tones generated in code: listening beep, done chime, scan tick.
final class ToneService {
    func play(_ t: Tone) {}
}
