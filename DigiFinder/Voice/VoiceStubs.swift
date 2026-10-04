// Wave 1 compiling stubs. The Voice-Feedback-Network-System agent replaces these (one file per type).
import Foundation
import DigiFinderCore

/// On-device SFSpeechRecognizer; ends on volume down, ~1.5 s silence or ~10 s (§5.10).
final class SpeechVoiceInput: VoiceInput {
    private(set) var isListening = false
    func listen(maxSeconds: Double) async -> VoiceResult { .empty(noisy: false) }
    func finish() {}
    func cancel() {}
}

/// Simulator / debug panel: typed requests stand in for speech.
final class TypedVoiceInput: VoiceInput {
    private(set) var isListening = false
    func listen(maxSeconds: Double) async -> VoiceResult { .cancelled }
    func finish() {}
    func cancel() {}
    /// Called by the debug panel with a typed request.
    func submit(_ text: String) {}
}
