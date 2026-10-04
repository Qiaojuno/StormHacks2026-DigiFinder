import Foundation

/// Extra voice-input controls beyond the frozen `VoiceInput` (see CONTRACT_CHANGES.md).
/// Use `(env.voice as? VoiceInputControl)` until the contract adopts them.
protocol VoiceInputControl: AnyObject {
    /// Called on the main queue when the microphone or speech-recognition permission is denied
    /// (the runner sends `.system(.micDenied)`). `listen` then returns `.empty(noisy: false)`.
    var onPermissionDenied: (() -> Void)? { get set }
    var permissionDenied: Bool { get }
    /// Asks for microphone + speech recognition up front (e.g. at session start). Returns true when both are granted.
    func requestPermissions() async -> Bool
    /// Recognition hints, e.g. catalog brand names (§9 `contextualStrings`).
    var contextualStrings: [String] { get set }
}
